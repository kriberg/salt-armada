{% set armada = salt["pillar.get"]("armada", {}) %}
armada platform dependencies:
  pkg.installed:
    - names: 
      - git
      - nginx
      - nodejs
      - nodejs-legacy
      - npm
      - openssl

armada service directory:
  file.directory:
    - name: /srv/www/armada
    - makedirs: True
    - user: {{ armada.static_user }}
    - group: {{ armada.static_group }}
    
javascript tools:
  npm.installed:
    - pkgs:
      - grunt-cli
      - bower
      - webpack
    - require:
      - pkg: armada platform dependencies

#
# Code checkout and nginx config
#

{% if not armada.debug %}
armada code:
  git.latest:
    - name: https://github.com/kriberg/armada.git
    - target: /srv/www/armada/
    - user: {{ armada.static_user }}
    - require:
      - pkg: armada platform dependencies
      - file: armada service directory

proper rights:
  file.directory:
    - name: /srv/www/armada
    - user: {{ armada.static_user }}
    - group: {{ armada.static_group }}
    - recurse:
      - user
      - group

generate dhparam:
  cmd.run:
    - name: 'openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048'
    - onlyif: 'test ! -f /etc/ssl/certs/dhparam.pem'

armada site config:
  file.managed:
    - name: /etc/nginx/sites-available/armada-site
    - source: salt://armada/armada/armada-site.jinja
    - template: jinja
    - context:
      armada: {{ armada|yaml }}
    - require:
      - pkg: armada platform dependencies

enabled site:
  file.symlink:
    - name: /etc/nginx/sites-enabled/armada-site
    - target: /etc/nginx/sites-available/armada-site
    - require:
      - file: armada site config

npm bootstrap:
  npm.bootstrap:
    - name: /srv/www/armada
    - user: {{ armada.static_user }}
    - require:
      - npm: javascript tools
      - file: proper rights
      - file: armada service directory


build bundle:
  cmd.run:
    - name: gulp
    - cwd: /srv/www/armada
    - user: {{ armada.static_user }}
    - require:
      - npm: npm bootstrap
      - file: proper rights
{% else %}

armada site config:
  file.managed:
    - name: /etc/nginx/sites-available/armada-debug
    - source: salt://armada/armada/armada-debug.jinja
    - template: jinja
    - context:
      armada: {{ armada|yaml }}
    - require:
      - pkg: armada platform dependencies

enabled site:
  file.symlink:
    - name: /etc/nginx/sites-enabled/armada-debug
    - target: /etc/nginx/sites-available/armada-debug
    - require:
      - file: armada site config
{% endif %}

#
# Restart nginx
#

nginx service:
  service.running:
    - name: nginx
    - enable: True
    - running: True
    - require:
      - pkg: armada platform dependencies
      - file: armada site config
      - file: enabled site
      {% if not armada.debug %}
      - git: armada code
      {% endif %}
    - watch:
      - file: armada site config
      - file: enabled site
