{% set stationspinner = salt["pillar.get"]("stationspinner", {}) %}
{% set db = salt["pillar.get"]("postgres", {}) %}

include:
  - .base

uwsgi_dependencies:
  pkg.installed:
    - names:
      - uwsgi
      - uwsgi-plugin-python

uwsgi_service:
  service.running:
    - name: uwsgi
    - enable: True
    - reload: True
    - require:
      - pkg: uwsgi_dependencies

# Installed and configured. Now we just need uwsgi and webserver to setup

stationspinner_uwsgi_config:
  file.managed:
    - name: /etc/uwsgi.d/stationspinner.ini
    - user: stationspinner
    - group: {{ stationspinner.static_group }}
    - source: salt://armada/stationspinner/files/stationspinner.ini.jinja
    - template: jinja
    - context:
      stationspinner: {{ stationspinner|yaml }}
    - require:
      - user: stationspinner_user

{% if not stationspinner.debug %}
stationspinner_trigger_uwsgi_reload:
  cmd.run:
    - name: 'touch /srv/www/stationspinner/reload-stationspinner'
    - user: stationspinner
    - shell: /bin/bash
    - require:
      - service: uwsgi_service

stationspinner_collect_static_files:
  cmd.run: 
    - name: 'source ../env/bin/activate; echo yes | python manage.py collectstatic'
    - user: stationspinner
    - shell: /bin/bash
    - cwd: '/srv/www/stationspinner/web'
    - require:
      - git: stationspinner_code

{% endif %}

