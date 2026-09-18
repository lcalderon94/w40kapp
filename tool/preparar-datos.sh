#!/usr/bin/env bash
# Deja el dataset en español donde la app lo espera.
#
# Los datos no están en el repositorio: se generan traduciendo los JSON originales de BSData, que
# sí lo están. Son 48 MB que cambian con cada refresco de upstream, así que versionarlos sería
# guardar dos veces lo mismo y ensuciar cada diff.
set -euo pipefail
raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -d "$raiz/data/bsdata-es" ]]; then
  echo "Falta data/bsdata-es. Generándolo con el pipeline…"
  (cd "$raiz/pipeline" && mvn -q spring-boot:run -Dspring-boot.run.arguments="apply")
fi

mkdir -p "$raiz/app/assets/datos"
rm -f "$raiz/app/assets/datos"/*.json
cp "$raiz/data/bsdata-es"/*.json "$raiz/app/assets/datos/"

# Las opciones de equipo tal y como las dice la hoja impresa. Esto sí está en el repositorio —son
# 200 KB de texto que no cambian con cada refresco de upstream— y va aparte de los catálogos
# porque no es un catálogo: no se resuelve ni se valida, solo se lee.
mkdir -p "$raiz/app/assets/notas"
cp "$raiz/data/wargear/notas-de-equipo.json" "$raiz/app/assets/notas/"

echo "Listo: $(ls "$raiz/app/assets/datos" | wc -l) ficheros en app/assets/datos"
