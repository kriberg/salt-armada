{% set stationspinner = salt["pillar.get"]("stationspinner", {}) %}
{% set db = salt["pillar.get"]("postgres", {}) %}
include:
  - .base

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

logrotation:
  file.managed:
    - name: /etc/logrotate.d/stationspinner
    - source: salt://armada/stationspinner/files/stationspinner.logrotate
    - require:
      - file: celery logdir

celery rundir:
  file.directory:
    - name: /srv/www/stationspinner/run
    - user: stationspinner
    - group: celery
    - mode: 775

celeryd config:
  file.managed:
    - name: /etc/conf.d/stationspinner-worker
    - source: salt://armada/stationspinner/files/stationspinner-worker.conf.jinja
    - template: jinja
    - context:
      stationspinner: {{ stationspinner|yaml }}
    - require:
      - pkg: celery dist

celerybeat config:
  file.managed:
    - name: /etc/conf.d/stationspinner-beat
    - source: salt://armada/stationspinner/files/stationspinner-beat.conf
    - require:
      - pkg: celery dist

celeryd initscript:
  file.managed:
    - name: /lib/systemd/system/stationspinner-worker.service
    - source: salt://armada/stationspinner/files/stationspinner-worker.service
    - mode: 755
    - require:
      - file: celeryd config

celerybeat initscript:
  file.managed:
    - name: /lib/systemd/system/stationspinner-beat.service
    - source: salt://armada/stationspinner/files/stationspinner-beat.service
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
    - name: systemctl restart stationspinner-worker
    - watch:
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
    - name: systemctl restart stationspinner-beat; systemctl restart stationspinner-beat
    - watch:
      - git: stationspinner code

{% endif %}

bootstrap universe:
  cmd.run: 
    - name: 'source ../env/bin/activate; python manage.py bootstrap'
    - user: stationspinner
    - shell: /bin/bash
    - cwd: '/srv/www/stationspinner/web'

{% for market in stationspinner.markets %}
{{ market }} market indexing:
  cmd.run: 
    - name: 'source ../env/bin/activate; python manage.py addmarket "{{ market }}"'
    - user: stationspinner
    - shell: /bin/bash
    - cwd: '/srv/www/stationspinner/web'
{% endfor %}

