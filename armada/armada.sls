{% set armada = salt["pillar.get"]("armada", {}) %}
platform dependencies:
  pkg.installed:
    - names: 
      - git
      - nginx
      - nodejs
      - nodejs-legacy
      - npm

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
    - require:
      - pkg: platform dependencies

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
      - pkg: platform dependencies
      - file: armada service directory

armada site config:
  file.managed:
    - name: /etc/nginx/sites-available/armada-site
    - source: salt://armada/armada-site.jinja
    - template: jinja
    - context:
      armada: {{ armada|yaml }}
    - require:
      - pkg: platform dependencies

enabled site:
  file.symlink:
    - name: /etc/nginx/sites-enabled/armada-site
    - target: /etc/nginx/sites-available/armada-site
    - require:
      - file: armada site config

npm bootstrap:
  npm.bootstrap:
    - name: /srv/www/armada
    - require:
      - npm: javascript tools
      - file: armada service directory

bower bootstrap:
  cmd.run:
    - name: bower install --allow-root
    - cwd: /srv/www/armada
    - require:
      - npm: npm bootstrap

proper rights:
  file.directory:
    - name: /srv/www/armada
    - user: {{ armada.static_user }}
    - group: {{ armada.static_group }}
    - recurse:
      - user
      - group

{% else %}

armada site config:
  file.managed:
    - name: /etc/nginx/sites-available/armada-debug
    - source: salt://armada/armada-debug.jinja
    - template: jinja
    - context:
      armada: {{ armada|yaml }}
    - require:
      - pkg: platform dependencies

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
      - pkg: platform dependencies
      - file: armada site config
      - file: enabled site
      {% if not armada.debug %}
      - git: armada code
      {% endif %}
    - watch:
      - file: armada site config
      - file: enabled site
