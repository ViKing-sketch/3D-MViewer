# Образ CLI-конвертера MVP (аналитический IFC-мешер, без OCCT).
# Сборка: docker build -t fbvconv .
# Запуск: docker run --rm -v "$PWD":/data fbvconv /data/in.ifc -o /data/out.fbvpkg
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential cmake ninja-build ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY . .
RUN cmake --preset linux-gcc-release && cmake --build --preset linux-gcc-release
ENTRYPOINT ["/src/build/linux-gcc-release/converter/fbvconv"]
