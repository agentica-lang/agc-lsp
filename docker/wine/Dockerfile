FROM debian:trixie-slim AS fetch
ARG AGENTICA_VERSION
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /download
RUN test -n "$AGENTICA_VERSION" \
    && archive="agentica-${AGENTICA_VERSION}-windows-x86_64" \
    && base="https://github.com/sonic182/agentica/releases/download/${AGENTICA_VERSION}" \
    && curl -fsSLO "${base}/${archive}.zip" \
    && curl -fsSLO "${base}/SHA256SUMS" \
    && sha256sum -c --ignore-missing SHA256SUMS \
    && unzip -q "${archive}.zip" \
    && mv "${archive}/bin" /agentica

FROM debian:trixie-slim
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates wine wine64 \
    && rm -rf /var/lib/apt/lists/*
ENV WINEDEBUG=-all WINEPREFIX=/wine WINEPATH='Z:\agentica'
RUN wineboot --init
COPY --from=fetch /agentica /agentica
RUN printf '#!/bin/sh\nexec wine /agentica/agentica.exe "$@"\n' > /usr/local/bin/agentica \
    && chmod +x /usr/local/bin/agentica
