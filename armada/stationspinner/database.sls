{% set stationspinner = salt["pillar.get"]("stationspinner", {}) %}
{% set db = salt["pillar.get"]("postgres", {}) %}
include:
  - postgres
  - .base

database dependencies:
  pkg.installed:
    - names:
      - redis-server
      - rabbitmq-server
      - postgresql-contrib-9.5


# RabbitMQ setup

rabbit monitoring:
  rabbitmq_plugin.enabled:
    - name: rabbitmq_management

rabbitmq restart:
  cmd.wait:
    - name: 'service rabbitmq-server restart'
    - watch:
      - rabbitmq_plugin: rabbit monitoring

rabbit armada user:
  rabbitmq_user.present:
    - name : {{ stationspinner.rabbitmq.user }}
    - password: {{ stationspinner.rabbitmq.password }}
    - force: True
    - tags:
      - monitoring
      - user
    - perms:
      - '/':
        - '.*'
        - '.*'
        - '.*'
    - require:
      - rabbitmq_plugin: rabbit monitoring
      - cmd: rabbitmq restart

rabbit armada vhost:
  rabbitmq_vhost.present:
    - name: {{ stationspinner.rabbitmq.vhost }}
    - require:
      - rabbitmq_user: rabbit armada user

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
    - shell: /bin/bash
    - require:
      - file: latest postgresql dump

drop sde database:
  cmd.wait:
    - name: 'psql -c "drop schema public cascade" sde'
    - user: postgres
    - watch:
      - file: latest postgresql dump

create sde database:
  cmd.wait:
    - name: 'psql -c "create schema public" sde'
    - user: stationspinner
    - watch:
      - file: latest postgresql dump
      - cmd: drop sde database

import sde:
  cmd.run:
    - name: 'pg_restore --role=stationspinner -n public -O -j 4 -d sde /srv/www/stationspinner/sde/postgres-latest.dmp'
    - user: postgres
    - shell: /bin/bash
    - onlyif: 'test "$(psql -c "\d" sde)" = "No relations found."'
    - require:
      - cmd: unpacked dump
      - cmd: drop sde database

ltree extension:
  cmd.run:
    - name: 'psql -c "create extension if not exists ltree" stationspinner'
    - user: postgres
    - shell: /bin/bash

unaccent extension:
  cmd.run:
    - name: 'psql -c "create extension if not exists unaccent" stationspinner'
    - user: postgres
    - shell: /bin/bash

migrate stationspinner:
  cmd.run:
    - name: 'source ../env/bin/activate && yes "yes" | python manage.py migrate'
    - cwd: '/srv/www/stationspinner/web'
    - user: stationspinner
    - shell: /bin/bash
    - require:
      - cmd: import sde
      - cmd: stationspinner venv
      - cmd: ltree extension
evespai grants:
  cmd.run:
    - name: '/srv/www/stationspinner/web/tools/fix_evespai_grants'
    - user: stationspinner
    - shell: /bin/bash
    - require:
      - cmd: import sde
      - cmd: migrate stationspinner
