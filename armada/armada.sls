{% set armada = salt["pillar.get"]("armada", {}) %}
platform dependencies:
  pkg.installed:
    - names: 
      - git
      - nginx

armada service directory:
  file.directory:
    - name: /srv/www/armada
    - makedirs: True
    - user: {{ armada.static-user }}
    - group: {{ armada.static-group }}

{% if not armada.debug %}
armada code:
  git.latest:
    - name: https://github.com/kriberg/armada.git
    - target: /srv/www/armada/
    - user: {{ armada.static-user }}
    - require:
      - pkg: platform dependencies
      - file: armada service directory
{% endif %}

armada site config:
  file.managed:
    - name: /etc/nginx/sites-available/armada-site
    - source: salt://armada/armada-site.jinja
    - template: jinja
    - context:
      armada: {{ armada|yaml }}
    - require:
      - pkg: platform dependencies


nginx service:
  service.running:
    - name: nginx
    - enable: True
    - running: True
    - require:
      - pkg: platform dependencies
      - file: armada site config
      {% if not armada.debug %}
      - git: armada code
      {% endif %}
