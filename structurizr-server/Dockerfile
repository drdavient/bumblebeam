# Structurizr Server — open core, built from source (Apache-2.0).
# The prebuilt structurizr/structurizr image license-gates `server` mode; the
# gate does not exist in the open-core source (verified: the check's strings
# appear nowhere in it), which is the documented free path. Mirrors upstream's
# structurizr-application/Dockerfiles/eclipse-temurin-noble runtime image.

FROM eclipse-temurin:21-jdk-noble AS build
ARG STRUCTURIZR_REF=9ff16634c3b8574584262ae8545510bbb1d1b4bd
RUN apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*
RUN git clone https://github.com/structurizr/structurizr.git /src \
    && cd /src && git checkout "$STRUCTURIZR_REF"
WORKDIR /src
RUN ./mvnw -q -DskipTests package

# One-shot renderer for publish-time PNG/thumbnail export (needs a browser).
# Never runs as a service — publish.sh invokes it and it exits. Upstream's own
# Playwright base pin.
FROM mcr.microsoft.com/playwright/java:v1.59.0-noble AS renderer
ENV PORT=8080
COPY --from=build /src/structurizr-application/target/structurizr-*.war /usr/local/structurizr.war
COPY --from=build /src/structurizr-themes /usr/local/structurizr-themes
COPY --from=build /src/structurizr-application/Dockerfiles/structurizr.sh /usr/local/structurizr.sh
RUN chmod +x /usr/local/structurizr.sh
WORKDIR /usr/local/structurizr
ENTRYPOINT ["/usr/local/structurizr.sh"]

FROM eclipse-temurin:21-jre-noble
ENV PORT=8080
COPY --from=build /src/structurizr-application/target/structurizr-*.war /usr/local/structurizr.war
COPY --from=build /src/structurizr-themes /usr/local/structurizr-themes
COPY --from=build /src/structurizr-application/Dockerfiles/structurizr.sh /usr/local/structurizr.sh
RUN chmod +x /usr/local/structurizr.sh
EXPOSE ${PORT}
WORKDIR /usr/local/structurizr
ENTRYPOINT ["/usr/local/structurizr.sh"]
