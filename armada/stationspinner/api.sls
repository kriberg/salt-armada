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

drop sde database:
  cmd.wait:
    - name: 'psql -c "drop schema public cascade; create schema public" sde'
    - user: stationspinner
    - watch:
      - file: latest postgresql dump

import sde:
  cmd.run:
    - name: 'pg_restore --role=stationspinner -n public -O -j 4 -d sde /srv/www/stationspinner/sde/postgres-latest.dmp'
    - user: postgres
    - onlyif: 'test "$(psql -c "\d" sde)" = "No relations found."'
    - require:
      - cmd: unpacked dump
      - cmd: drop sde database

ltree extension:
  cmd.run:
    - name: 'psql -c "create extension if not exists ltree" stationspinner'
    - user: postgres

unaccent extension:
  cmd.run:
    - name: 'psql -c "create extension if not exists unaccent" stationspinner'
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

character_asset:
  cmd.run:
    - name: 'psql -f stationspinner/character/sql/asset.sql stationspinner'
    - cwd: '/srv/www/stationspinner/web'
    - user: stationspinner
    - onlyif: test "$(psql -t -A -c "select count(*) from information_schema.tables where table_name='corporation_asset'" stationspinner)" = "0"
    - require:
      - cmd: migrate stationspinner

corporation_asset:
  cmd.run:
    - name: 'psql -f stationspinner/corporation/sql/asset.sql stationspinner'
    - cwd: '/srv/www/stationspinner/web'
    - user: stationspinner
    - onlyif: test "$(psql -t -A -c "select count(*) from information_schema.tables where table_name='corporation_asset'" stationspinner)" = "0"
    - require:
      - cmd: migrate stationspinner

evespai grants:
  cmd.run:
    - name: '/srv/www/stationspinner/web/tools/fix_evespai_grants'
    - user: stationspinner
    - require:
      - cmd: import sde
      - cmd: migrate stationspinner

{#
Installed and configured. Now we just need uwsgi and webserver to setup
#}

uwsgi config:
  file.managed:
    - name: /etc/uwsgi/apps-available/stationspinner.ini
    - source: salt://armada/stationspinner/files/stationspinner.ini

{#
This should trigger the uwsgi emperor to start stationspinner
#}
{% if not stationspinner.debug %}
uwsgi enabled:
  file.symlink:
    - name: /etc/uwsgi/apps-enabled/stationspinner.ini
    - target: /etc/uwsgi/apps-available/stationspinner.ini
{% endif %}

{% if not stationspinner.debug %}
trigger uwsgi reload:
  cmd.run:
    - name: 'touch /srv/www/stationspinner/reload-stationspinner'
    - user: stationspinner
    - require:
      - file: uwsgi enabled

{% endif %}

