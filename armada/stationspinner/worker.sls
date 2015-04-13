{% set stationspinner = salt["pillar.get"]("stationspinner", {}) %}
{% set db = salt["pillar.get"]("postgres", {}) %}

stationspinner user:
  user.present:
    - name: stationspinner

platform dependencies:
  pkg.installed:
    - names:
      - git
      - python-virtualenv
      - python-pip

stationspinner service directory:
  file.directory:
    - name: /srv/www/stationspinner
    - makedirs: True
    - user: stationspinner
    - group: stationspinner

{% if not stationspinner.debug %}
stationspinner code:
  git.latest:
    - name: https://github.com/kriberg/stationspinner.git
    - target: /srv/www/stationspinner/web
    - user: stationspinner
    - submodules: True
    - require:
      - pkg: platform dependencies
      - user: stationspinner user
      - file: stationspinner service directory
{% endif %}

stationspinner venv:
  cmd.run:
    - name: virtualenv /srv/www/stationspinner/env
    - onlyif: 'test ! -f /srv/www/stationspinner/env/bin/activate'
    - user: stationspinner
    - require:
      - pkg: platform dependencies
      - user: stationspinner user
      - file: stationspinner service directory

stationspinner reqs:
  cmd.run:
    - name: 'source ../env/bin/activate && pip install -r requirements.txt'
    - cwd: '/srv/www/stationspinner/web'
    - user: stationspinner
    - require:
      - cmd: stationspinner venv

stationspinner local settings:
  file.managed:
    - name: /srv/www/stationspinner/web/stationspinner/local_settings.py
    - source: file:///srv/www/stationspinner/web/stationspinner/local_settings.py.jinja
    - template: jinja
    - user: stationspinner
    - group: stationspinner
    - mode: 660
    - context:
      stationspinner: {{ stationspinner|yaml }}
      db: {{ db|yaml }}
    {% if not stationspinner.debug %}
    - require:
      - git: stationspinner code
    {% endif %}

# Celery configuration

celery dist:
  pkg.installed:
    - name: celeryd

celery logdir:
  file.directory:
    - name: /srv/www/stationspinner/log
    - makedirs: True
    - user: stationspinner
    - group: celery
    - mode: 775

celery rundir:
  file.directory:
    - name: /srv/www/stationspinner/run
    - user: stationspinner
    - group: celery
    - mode: 775

celeryd config:
  file.managed:
    - name: /etc/default/stationspinner-worker
    - source: salt://armada/stationspinner/files/stationspinner-worker.conf
    - require:
      - pkg: celery dist

celerybeat config:
  file.managed:
    - name: /etc/default/stationspinner-beat
    - source: salt://armada/stationspinner/files/stationspinner-beat.conf
    - require:
      - pkg: celery dist

celeryd initscript:
  file.managed:
    - name: /etc/init.d/stationspinner-worker
    - source: salt://armada/stationspinner/files/stationspinner-worker.init
    - mode: 755
    - require:
      - file: celeryd config

celerybeat initscript:
  file.managed:
    - name: /etc/init.d/stationspinner-beat
    - source: salt://armada/stationspinner/files/stationspinner-beat.init
    - mode: 755
    - require:
      - file: celerybeat config


{% if not stationspinner.debug %}
celeryd service:
  service.running:
    - name: stationspinner-worker
    - enable: True
    - running: True
    - require:
      - file: celeryd initscript
      - file: celery rundir
      - file: celery logdir

manual restart celeryd:
  cmd.wait:
    - name: service stationspinner-worker restart
    - watch:
      - cmd: migrate stationspinner
      - git: stationspinner code

celerybeat service:
  service.running:
    - name: stationspinner-beat
    - enable: True
    - running: True
    - require:
      - file: celerybeat initscript
      - file: celery rundir
      - file: celery logdir

manual restart beat:
  cmd.wait:
    - name: service stationspinner-beat stop; service stationspinner-beat start
    - watch:
      - cmd: migrate stationspinner
      - git: stationspinner code

{% endif %}
