{% set config = salt["pillar.get"]("evespai", {}) %}

dependencies:
  pkg.installed:
    - name: supybot

bot user:
  user.present:
    - name: {{ config.username }}
    - home: /home/{{ config.username }}


