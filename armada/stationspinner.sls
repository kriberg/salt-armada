include:
  - postgres
  - uwsgi
{% set stationspinner = salt["pillar.get"]("stationspinner", {}) %}
{% set db = salt["pillar.get"]("postgres", {}) %}

{#
The user which will run the services
#}


stationspinner user:
  user.present:
    - name: stationspinner
    - groups:
      - uwsgi


{#
get the code, setup virtualenv and install dependencies
#}

platform dependencies:
  pkg.installed:
    - names:
      - git
      - python-virtualenv
      - python-pip
      - postgresql-contrib-9.4
      - redis-server

stationspinner service directory:
  file.directory:
    - name: /srv/www/stationspinner
    - makedirs: True
    - user: stationspinner
    - group: stationspinner

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
    - require:
      - git: stationspinner code

{#
Download and import the SDE from fuzzyesteve
#}
dump dir:
  file.directory:
    - name: /srv/www/stationspinner/sde
    - makedirs: True
    - user: stationspinner
    - group: stationspinner

latest postgresql dump:
  file.managed:
    - name: /srv/www/stationspinner/sde/postgres-latest.dmp.bz2
    - source: https://www.fuzzwork.co.uk/dump/postgres-latest.dmp.bz2
    - source_hash: https://www.fuzzwork.co.uk/dump/postgres-latest.dmp.bz2.md5
    - user: stationspinner
    - group: stationspinner
    - require:
      - file: dump dir

delete old dump:
  cmd.wait:
    - name: 'rm postgres-latest.dmp'
    - cwd: '/srv/www/stationspinner/sde'
    - onlyif: 'test -f /srv/www/stationspinner/sde/postgres-latest.dmp'
    - watch:
      - file: latest postgresql dump

unpacked dump:
  cmd.run:
    - name: 'bunzip2 -k postgres-latest.dmp.bz2'
    - cwd: '/srv/www/stationspinner/sde'
    - onlyif: 'test ! -f postgres-latest.dmp'
    - user: stationspinner
    - group: stationspinner
    - require:
      - file: latest postgresql dump

import sde:
  cmd.run:
    - name: 'pg_restore --role=stationspinner -n public -O -j 4 -d sde /srv/www/stationspinner/sde/postgres-latest.dmp'
    - user: postgres
    - onlyif: 'test "$(psql -c "\d" sde)" = "No relations found."'
    - require:
      - cmd: unpacked dump

ltree extension:
  cmd.run:
    - name: 'psql -c "create extension if not exists ltree" stationspinner'
    - user: postgres

migrate stationspinner:
  cmd.run:
    - name: 'source ../env/bin/activate && python manage.py migrate'
    - cwd: '/srv/www/stationspinner/web'
    - user: stationspinner
    - require:
      - cmd: import sde
      - cmd: stationspinner venv
      - cmd: ltree extension

evespai grants:
  cmd.run:
    - name: '/srv/www/stationspinner/web/tools/fix_evespai_grants'
    - user: postgres
    - require:
      - cmd: import sde
      - cmd: migrate stationspinner

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
    - source: salt://armada/stationspinner-worker.conf
    - require:
      - pkg: celery dist

celerybeat config:
  file.managed:
    - name: /etc/default/stationspinner-beat
    - source: salt://armada/stationspinner-beat.conf
    - require:
      - pkg: celery dist

celeryd initscript:
  file.managed:
    - name: /etc/init.d/stationspinner-worker
    - source: salt://armada/stationspinner-worker.init
    - mode: 755
    - require:
      - file: celeryd config

celerybeat initscript:
  file.managed:
    - name: /etc/init.d/stationspinner-beat
    - source: salt://armada/stationspinner-beat.init
    - mode: 755
    - require:
      - file: celerybeat config


celeryd service:
  service.running:
    - name: stationspinner-worker
    - enable: True
    - running: True
    - reload: True
    - watch:
      - cmd: migrate stationspinner
    - require:
      - file: celeryd initscript
      - file: celery rundir
      - file: celery logdir

celerybeat service:
  service.running:
    - name: stationspinner-beat
    - enable: True
    - running: True
    - reload: True
    - watch:
      - cmd: migrate stationspinner
    - require:
      - file: celerybeat initscript
      - file: celery rundir
      - file: celery logdir
{#
Installed and configured. Now we just need uwsgi and webserver to setup
#}

uwsgi config:
  file.managed:
    - name: /etc/uwsgi/apps-available/stationspinner.ini
    - source: salt://armada/stationspinner.ini

{#
This should trigger the uwsgi emperor to start stationspinner
#}
#app enabled:
#  file.symlink:
#    - name: /etc/uwsgi/apps-enabled/stationspinner.ini
#    - target: /etc/uwsgi/apps-available/stationspinner.ini

bootstrap universe:
  cmd.run: 
    - name: 'source ../env/bin/activate; python manage.py runtask universe.update_universe'
    - user: stationspinner
    - cwd: '/srv/www/stationspinner/web'
    - require:
      - cmd: migrate stationspinner

    #- onlyif: 'test "psql -t -c "select count(*) from universe_apicall" stationspinner|tr -d \' \'" = "0"'

