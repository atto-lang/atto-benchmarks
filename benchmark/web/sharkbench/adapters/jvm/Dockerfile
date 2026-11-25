# Admission-only runtime image. Supply the resolved immutable Ubuntu digest.
ARG BASE_IMAGE=ubuntu@sha256:562111b88caa79c71391c0c4d3c2114a7d5c35915c20561fd893cb1e07929e6b
FROM ${BASE_IMAGE}
WORKDIR /app
COPY --chown=65532:65532 jdk/ /opt/jdk/
COPY --chown=65532:65532 classes/ /app/classes/
COPY --chown=65532:65532 deps/ /app/deps/
COPY --chown=65532:65532 library/ /app/library/
COPY --chown=65532:65532 sharkbench-web.atto classpath.txt /app/
COPY --chown=65532:65532 launch.sh /app/launch.sh
ENV JAVA_HOME=/opt/jdk HOME=/tmp
USER 65532:65532
EXPOSE 5001
ENTRYPOINT ["/bin/sh","/app/launch.sh"]
