{% set armada = salt["pillar.get"]("armada", {}) %}
node_5:
  cmd.run:
    - name: 'curl --silent --location https://rpm.nodesource.com/setup_5.x | bash -'
    - onlyif: 'test ! -f /etc/apt/sources.list.d/nodesource.list'

armada_platform_dependencies:
  pkg.installed:
    - names: 
      - git
      - nginx
      - nodejs
      - gcc
      - gcc-c++
      - openssl-devel
    - require:
      - cmd: node_5

armada_service_directory:
  file.directory:
    - name: /srv/www/armada/
    - makedirs: True
    - user: stationspinner
    - group: stationspinner
    
armada_javascript_tools:
  npm.installed:
    - pkgs:
      - bower
      - webpack@1.12.14
      - gulp
    - require:
      - pkg: armada_platform_dependencies

#
# Code checkout and nginx config
#

{% if not armada.debug %}
armada_code:
  git.latest:
    - name: https://github.com/kriberg/armada.git
    - target: /srv/www/armada/
    - user: stationspinner
    - require:
      - pkg: armada_platform_dependencies
      - file: armada_service_directory

nginx_generate_dhparam:
  cmd.run:
    - name: 'openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048'
    - onlyif: 'test ! -f /etc/ssl/certs/dhparam.pem'

armada_site_config:
  file.managed:
    - name: /etc/nginx/conf.d/armada-site.conf
    - source: salt://armada/armada/armada-site.conf.jinja
    - template: jinja
    - context:
      armada: {{ armada|yaml }}
    - require:
      - pkg: armada_platform_dependencies

armada_npm_bootstrap:
  npm.bootstrap:
    - name: /srv/www/armada
    - user: stationspinner
    - require:
      - npm: armada_javascript_tools
      - file: armada_service_directory


armada_build_bundle:
  cmd.run:
    - name: gulp
    - cwd: /srv/www/armada
    - user: stationspinner
    - require:
      - npm: armada_npm_bootstrap

{% else %}

armada_site_config:
  file.managed:
    - name: /etc/nginx/conf.d/armada-debug.conf
    - source: salt://armada/armada/armada-debug.conf.jinja
    - template: jinja
    - context:
      armada: {{ armada|yaml }}
    - require:
      - pkg: armada_platform_dependencies

{% endif %}

#
# Restart nginx
#

nginx_service:
  service.running:
    - name: nginx
    - enable: True
    - running: True
    - require:
      - pkg: armada_platform_dependencies
      - file: armada_site_config
      {% if not armada.debug %}
      - git: armada_code
      {% endif %}
    - watch:
      - file: armada_site_config

