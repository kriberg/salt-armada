{% set stationspinner = salt["pillar.get"]("stationspinner", {}) %}
{% set db = salt["pillar.get"]("postgres", {}) %}

postgresql repository:
  pkgrepo.managed:
    - humanname: PGDG 9.4
    {% if grains['os_family'] == 'RedHat' %}
    - baseurl: http://yum.postgresql.org/9.4/redhat/rhel-$releasever-$basearch
    - gpgkey: http://yum.postgresql.org/RPM-GPG-KEY-PGDG-94
    - gpgcheck: 1
    {% else %}
    - name: deb http://apt.postgresql.org/pub/repos/apt/ wheezy-pgdg main 9.4
    - keyid: ACCC4CF8
    - keyserver: keyserver.ubuntu.com
    {% endif %}

stationspinner user:
  user.present:
    - name: stationspinner
    - shell: /bin/bash
    - system: True

platform dependencies:
  pkg.installed:
    - names:
      - git
      - python-virtualenv
      - python-pip
      - libpq-dev
      - python-dev

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
    - shell: /bin/bash
    - require:
      - pkg: platform dependencies
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

