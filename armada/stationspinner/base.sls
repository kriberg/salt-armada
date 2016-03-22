{% set stationspinner = salt["pillar.get"]("stationspinner", {}) %}
{% set db = salt["pillar.get"]("postgres", {}) %}

postgresql repository:
  pkgrepo.managed:
    - humanname: PGDG 9.5
    - name: deb http://apt.postgresql.org/pub/repos/apt/ jessie-pgdg main
    - keyid: ACCC4CF8
    - keyserver: keyserver.ubuntu.com

stationspinner user:
  user.present:
    - name: stationspinner
    - shell: /bin/bash
    - system: True

stationspinner platform dependencies:
  pkg.installed:
    - names:
      - git
      - python-virtualenv
      - python-pip
      - libpq-dev
      - python-dev
      - libffi-dev

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
      - pkg: stationspinner platform dependencies
      - user: stationspinner user
      - file: stationspinner service directory
{% endif %}

stationspinner venv:
  cmd.run:
    - name: virtualenv /srv/www/stationspinner/env
    - onlyif: 'test ! -f /srv/www/stationspinner/env/bin/activate'
    - user: stationspinner
    - shell: /bin/bash
    - require:
      - pkg: stationspinner platform dependencies
      - user: stationspinner user
      - file: stationspinner service directory

stationspinner reqs:
  cmd.run:
    - name: 'source ../env/bin/activate && pip install -r requirements.txt'
    - cwd: '/srv/www/stationspinner/web'
    - user: stationspinner
    - shell: /bin/bash
    - require:
      - cmd: stationspinner venv

{% if stationspinner.debug %}
stationspinner development reqs:
  cmd.run:
    - name: 'source ../env/bin/activate && pip install -r development_reqs.txt'
    - cwd: '/srv/www/stationspinner/web'
    - user: stationspinner
    - shell: /bin/bash
    - require:
      - cmd: stationspinner venv
{% endif %}

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

