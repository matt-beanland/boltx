# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0
#
# Neo4j 5.26 LTS with a baked-in bolt server certificate, used by the
# neo4j-bolt5 compose service for the TLS integration tests. Certs are generated
# on the host by test/tls/gen_certs.sh and copied in here so they carry the
# ownership + 0600 permissions Neo4j requires (baking avoids the bind-mount
# permission failures you hit mounting a host-owned private key).
ARG NEO4J_VERSION=5.26.28
FROM neo4j:${NEO4J_VERSION}

COPY certs/server.crt /ssl/bolt/public.crt
COPY certs/server.key /ssl/bolt/private.key

RUN mkdir -p /ssl/bolt/trusted /ssl/bolt/revoked \
 && chown -R neo4j:neo4j /ssl \
 && chmod 600 /ssl/bolt/private.key \
 && chmod 644 /ssl/bolt/public.crt

# Bolt SSL policy, baked into the image so compose and CI's `docker run` both get
# it without repeating the env. tls_level OPTIONAL keeps plaintext bolt working
# (existing suite + healthcheck) while bolt+s / bolt+ssc exercise TLS.
ENV NEO4J_dbms_ssl_policy_bolt_enabled=true \
    NEO4J_dbms_ssl_policy_bolt_base__directory=/ssl/bolt \
    NEO4J_dbms_ssl_policy_bolt_private__key=private.key \
    NEO4J_dbms_ssl_policy_bolt_public__certificate=public.crt \
    NEO4J_dbms_ssl_policy_bolt_client__auth=NONE \
    NEO4J_server_bolt_tls__level=OPTIONAL
