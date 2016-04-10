{% set stationspinner = salt["pillar.get"]("stationspinner", {}) %}
{% set db = salt["pillar.get"]("postgres", {}) %}

stationspinner_user:
  user.present:
    - name: stationspinner
    - shell: /bin/bash
    - system: True

stationspinner_platform_dependencies:
  pkg.installed:
    - names:
      - git
      - python-virtualenv
      - python-pip
      - python-devel
      - libffi-devel
      - gcc
      - openssl-devel

stationspinner_service_directory:
  file.directory:
    - name: /srv/www/stationspinner
    - makedirs: True
    - user: stationspinner
    - group: stationspinner

{% if not stationspinner.debug %}
stationspinner_code:
  git.latest:
    - name: https://github.com/kriberg/stationspinner.git
    - target: /srv/www/stationspinner/web
    - user: stationspinner
    - submodules: True
    - require:
      - pkg: stationspinner_platform_dependencies
      - user: stationspinner_user
      - file: stationspinner_service_directory
{% endif %}

stationspinner_venv:
  cmd.run:
    - name: virtualenv /srv/www/stationspinner/env
    - onlyif: 'test ! -f /srv/www/stationspinner/env/bin/activate'
    - user: stationspinner
    - shell: /bin/bash
    - require:
      - pkg: stationspinner_platform_dependencies
      - user: stationspinner_user
      - file: stationspinner_service_directory

stationspinner_reqs:
  cmd.run:
    - name: 'source ../env/bin/activate && pip install -r requirements.txt'
    - cwd: '/srv/www/stationspinner/web'
    - user: stationspinner
    - shell: /bin/bash
    - require:
      - cmd: stationspinner_venv

{% if stationspinner.debug %}
stationspinner_development_reqs:
  cmd.run:
    - name: 'source ../env/bin/activate && pip install -r development_reqs.txt'
    - cwd: '/srv/www/stationspinner/web'
    - user: stationspinner
    - shell: /bin/bash
    - require:
      - cmd: stationspinner_venv
{% endif %}

stationspinner_local_settings:
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
      - git: stationspinner_code
    {% endif %}

