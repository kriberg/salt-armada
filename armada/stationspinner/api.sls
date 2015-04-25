{% set stationspinner = salt["pillar.get"]("stationspinner", {}) %}
{% set db = salt["pillar.get"]("postgres", {}) %}

include:
  - uwsgi
  - .base

uwsgi_member:
  user.present:
    - name: stationspinner
    - groups:
      - uwsgi

# Installed and configured. Now we just need uwsgi and webserver to setup

uwsgi config:
  file.managed:
    - name: /etc/uwsgi/apps-available/stationspinner.ini
    - source: salt://armada/stationspinner/files/stationspinner.ini

# This should trigger the uwsgi emperor to start stationspinner

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
    - shell: /bin/bash
    - require:
      - file: uwsgi enabled

collect static files:
  cmd.run: 
    - name: 'source ../env/bin/activate; echo yes | python manage.py collectstatic'
    - user: stationspinner
    - shell: /bin/bash
    - cwd: '/srv/www/stationspinner/web'

fix static files ownership:
  file.directory:
    - name: '{{ stationspinner.static_root }}'
    - group: '{{ stationspinner.static_group }}'
    - recurse:
      - group

{% endif %}

