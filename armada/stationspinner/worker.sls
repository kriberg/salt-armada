{% set stationspinner = salt["pillar.get"]("stationspinner", {}) %}
{% set db = salt["pillar.get"]("postgres", {}) %}
include:
  - .base

# Celery configuration
celery_logdir:
  file.directory:
    - name: /srv/www/stationspinner/log
    - makedirs: True
    - user: stationspinner
    - group: stationspinner
    - mode: 775

logrotation:
  file.managed:
    - name: /etc/logrotate.d/stationspinner
    - source: salt://armada/stationspinner/files/stationspinner.logrotate
    - require:
      - file: celery_logdir

celery_rundir:
  file.directory:
    - name: /srv/www/stationspinner/run
    - user: stationspinner
    - group: stationspinner
    - mode: 777

celery_worker_config:
  file.managed:
    - name: /etc/sysconfig/stationspinner-worker
    - source: salt://armada/stationspinner/files/stationspinner-worker.conf.jinja
    - template: jinja
    - context:
      stationspinner: {{ stationspinner|yaml }}

celery_beat_config:
  file.managed:
    - name: /etc/sysconfig/stationspinner-beat
    - source: salt://armada/stationspinner/files/stationspinner-beat.conf

celery_worker_unit:
  file.managed:
    - name: /etc/systemd/system/stationspinner-worker.service
    - source: salt://armada/stationspinner/files/stationspinner-worker.service
    - mode: 755
    - require:
      - file: celery_worker_config

celery_beat_unit:
  file.managed:
    - name: /etc/systemd/system/stationspinner-beat.service
    - source: salt://armada/stationspinner/files/stationspinner-beat.service
    - mode: 755
    - require:
      - file: celery_beat_config


{% if not stationspinner.debug %}
celery_worker_service:
  service.running:
    - name: stationspinner-worker
    - enable: True
    - running: True
    - require:
      - file: celery_worker_config
      - file: celery_rundir
      - file: celery_logdir
      - file: celery_worker_unit

celery_worker_trigger_restart:
  cmd.wait:
    - name: systemctl restart stationspinner-worker
    - watch:
      - git: stationspinner_code

celery_beat_service:
  service.running:
    - name: stationspinner-beat
    - enable: True
    - running: True
    - require:
      - file: celery_beat_config
      - file: celery_rundir
      - file: celery_logdir
      - file: celery_beat_unit

celery_beat_trigger_restart:
  cmd.wait:
    - name: systemctl stop stationspinner-beat; systemctl start stationspinner-beat
    - watch:
      - git: stationspinner_code


stationspinner_bootstrap_universe:
  cmd.run: 
    - name: 'source ../env/bin/activate; python manage.py bootstrap'
    - user: stationspinner
    - shell: /bin/bash
    - cwd: '/srv/www/stationspinner/web'
    - require:
      - service: celery_worker_service

{% for market in stationspinner.markets %}
{{ market }} market indexing:
  cmd.run: 
    - name: 'source ../env/bin/activate; python manage.py addmarket "{{ market }}"'
    - user: stationspinner
    - shell: /bin/bash
    - cwd: '/srv/www/stationspinner/web'
{% endfor %}

{% endif %}
