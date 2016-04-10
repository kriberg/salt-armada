{% set stationspinner = salt["pillar.get"]("stationspinner", {}) %}
{% set db = salt["pillar.get"]("postgres", {}) %}
include:
  - postgres
  - .base

postgres_maxfiles:
  file.managed:
    - name: '/etc/security/limits.d/postgres.conf'
    - contents:
      - 'postgres  hard  nofile  262433'
      - 'postgres  soft  nofile  262433'

postgres_in_path:
  file.managed:
    - name: '/etc/profile.d/postgresql.sh'
    - contents:
      - 'export PATH="$PATH:/usr/pgsql-9.5/bin"'

database_dependencies:
  pkg.installed:
    - names:
      - redis
      - rabbitmq-server
      - librabbitmq-devel
      - bzip2
      - pgbouncer

# PGBouncer setup
# ini_manage doesnt work :/
#pgbouncer_config:
#  ini.options_present:
#    - name: /etc/pgbouncer/pgbouncer.ini
#    - separator: '='
#    - sections:
#      databases:
#        - stationspinner: host=localhost dbname=stationspinner reserve_pool_size=256 max_db_connections=512
#        - sde: host=localhost dbname=sde reserve_pool_size=256 max_db_connections=512
#      pgbouncer:
#        - pool_mode: session
#        - listen_port: 6432
#        - listen_host: 127.0.0.1

pgbouncer_service:
  service.running:
    - name: pgbouncer
    - enable: True
    - reload: True
    - watch:
      - pkg: database_dependencies

# RabbitMQ setup

rabbit_monitoring:
  rabbitmq_plugin.enabled:
    - name: rabbitmq_management

rabbitmq_service:
  service.running:
    - name: rabbitmq-server
    - enable: True
    - reload: True
    - watch:
      - rabbitmq_plugin: rabbit_monitoring
      - pkg: database_dependencies

rabbit_armada_vhost:
  rabbitmq_vhost.present:
    - name: {{ stationspinner.rabbitmq.vhost }}

rabbit_armada_user:
  rabbitmq_user.present:
    - name : {{ stationspinner.rabbitmq.user }}
    - password: {{ stationspinner.rabbitmq.password }}
    - force: True
    - tags:
      - monitoring
      - user
    - perms:
      - 'armada':
        - '.*'
        - '.*'
        - '.*'
    - runas: rabbitmq
    - require:
      - rabbitmq_plugin: rabbit_monitoring
      - service: rabbitmq_service
      - rabbitmq_vhost: rabbit_armada_vhost

# Redis setup

redis_service:
  service.running:
    - name: redis
    - enable: True
    - reload: True
    - require:
      - pkg: database_dependencies

{#
Download and import the SDE from fuzzyesteve
#}
stationspinner_sde_dumpdir:
  file.directory:
    - name: /srv/www/stationspinner/sde
    - makedirs: True
    - user: stationspinner
    - group: stationspinner

sde_latest_postgresql_dump:
  file.managed:
    - name: /srv/www/stationspinner/sde/postgres-latest.dmp.bz2
    - source: https://www.fuzzwork.co.uk/dump/postgres-latest.dmp.bz2
    - source_hash: https://www.fuzzwork.co.uk/dump/postgres-latest.dmp.bz2.md5
    - user: stationspinner
    - group: stationspinner
    - require:
      - file: stationspinner_sde_dumpdir

sde_delete_old_dump:
  cmd.wait:
    - name: 'rm postgres-latest.dmp'
    - cwd: '/srv/www/stationspinner/sde'
    - onlyif: 'test -f /srv/www/stationspinner/sde/postgres-latest.dmp'
    - watch:
      - file: sde_latest_postgresql_dump

sde_unpacked_dump:
  cmd.run:
    - name: 'bunzip2 -k postgres-latest.dmp.bz2'
    - cwd: '/srv/www/stationspinner/sde'
    - onlyif: 'test ! -f postgres-latest.dmp'
    - user: stationspinner
    - group: stationspinner
    - shell: /bin/bash
    - require:
      - file: sde_latest_postgresql_dump

sde_drop_database:
  cmd.wait:
    - name: 'psql -c "drop schema public cascade" sde'
    - user: postgres
    - watch:
      - file: sde_latest_postgresql_dump

sde_create_database:
  cmd.wait:
    - name: 'psql -c "create schema public" sde'
    - user: stationspinner
    - watch:
      - file: sde_latest_postgresql_dump
      - cmd: sde_drop_database

sde_import_dump:
  cmd.run:
    - name: 'pg_restore --role=stationspinner -n public -O -j 4 -d sde /srv/www/stationspinner/sde/postgres-latest.dmp'
    - user: postgres
    - shell: /bin/bash
    - onlyif: 'test "$(psql -c "\d" sde)" = "No relations found."'
    - require:
      - cmd: sde_unpacked_dump
      - cmd: sde_drop_database

stationspinner_ltree_extension:
  cmd.run:
    - name: 'psql -c "create extension if not exists ltree" stationspinner'
    - user: postgres
    - shell: /bin/bash

stationspinner_unaccent_extension:
  cmd.run:
    - name: 'psql -c "create extension if not exists unaccent" stationspinner'
    - user: postgres
    - shell: /bin/bash

stationspinner_migrate_database:
  cmd.run:
    - name: 'source ../env/bin/activate && yes "yes" | python manage.py migrate'
    - cwd: '/srv/www/stationspinner/web'
    - user: stationspinner
    - shell: /bin/bash
    - require:
      - cmd: sde_import_dump
      - cmd: stationspinner_venv
      - cmd: stationspinner_ltree_extension
      - cmd: stationspinner_unaccent_extension

stationspinner_evespai_grants:
  cmd.run:
    - name: '/srv/www/stationspinner/web/tools/fix_evespai_grants'
    - user: stationspinner
    - shell: /bin/bash
    - require:
      - cmd: sde_import_dump
      - cmd: stationspinner_migrate_database
