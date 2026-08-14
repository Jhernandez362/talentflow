# Arquitectura base

Los servicios `postgres`, `n8n` y `frontend` comparten la red bridge `talentflow_network`.

- n8n persiste su configuracion en `n8n_data` y utiliza PostgreSQL mediante `postgres:5432`.
- PostgreSQL persiste sus datos en `postgres_data`.
- Los puertos publicados en el host se configuran en `.env`.
- Una futura integracion entre contenedores debera acceder a n8n mediante `http://n8n:5678`.

No se han creado tablas de dominio, workflows, prompts ni integraciones en este modulo.

