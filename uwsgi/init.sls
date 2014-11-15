dependencies:
  pkg.installed:
    - names: 
      - python-pip
      - python-dev

dist:
  cmd.run:
    - name: 'pip install uwsgi'
    - onlyif: 'test ! -f /usr/local/bin/uwsgi'
    - require:
      - pkg: dependencies

apps available:
  file.directory:
    - name: /etc/uwsgi/apps-available
    - makedirs: True

apps enabled:
  file.directory:
    - name: /etc/uwsgi/apps-enabled
    - makedirs: True

emperor config:
  file.managed:
    - name: /etc/uwsgi/emperor.ini
    - source: salt://uwsgi/emperor.ini
    - require:
      - file: apps available
      - file: apps enabled
      - cmd: dist

log group:
  group.present:
    - name: uwsgi
    - system: True

log directory:
  file.directory:
    - name: /var/log/uwsgi/
    - mode: 770
    - group: uwsgi
    - require:
      - group: log group

pid directory:
  file.directory:
    - name: /var/run/uwsgi
    - makedirs: True
    - mode: 775
    - group: uwsgi
    - require:
      - group: log group

upstart job:
  file.managed:
    - name: /etc/init/uwsgi.conf
    - source: salt://uwsgi/uwsgi.conf

uwsgi service:
  service.running:
    - name: uwsgi
    - enable: True
    - reload: True
    - watch:
      - file: upstart job
      - file: emperor config
