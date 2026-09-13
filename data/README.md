# data — dataset fuente (inglés)

Copia literal del dataset comunitario de Warhammer 40.000 11ª Edición que alimenta la app.
Es el **origen de verdad**: cuando Games Workshop publique erratas, cambios de puntos o
unidades nuevas, se vuelve aquí.

- **Repositorio origen**: https://github.com/BSData/wh40k-11e
- **Commit**: `a9fd7b49aab8d55e74561be6e3a51464e96254e3` (2026-09-12)
- **Procedencia completa**: [`SOURCE.json`](SOURCE.json) — commit, fecha y `sha256` de cada fichero

`bsdata/` no se edita nunca a mano. Cualquier cambio se hace regenerándolo desde upstream
(ver *Actualizar*). La traducción tampoco lo modifica:

- `translations/es/` — los lotes de traducción, que se versionan: son la memoria de traducción
- `bsdata-es/` — el dataset en español que produce `apply`. Es derivado y no se versiona; se
  regenera con el pipeline (ver [`pipeline/README.md`](../pipeline/README.md))

## Inventario

46 ficheros JSON en formato BattleScribe:

| Tipo | N.º | Qué es |
|---|---|---|
| `gameSystem` | 1 | `Warhammer 40,000.json` — reglas núcleo, tipos de perfil, categorías, stratagems comunes |
| `catalogue` | 36 | Una facción jugable por fichero. Cada capítulo de Space Marines es un catálogo independiente |
| `library` | 9 | Contenido compartido que los catálogos enlazan (Aeldari, Astra Militarum, Knights, Titans, Tyranids, Unaligned Forces…) |

## Dónde vive el texto

Tres sitios:

1. **`characteristics[]` con `name: "Description"`** → el texto está en la clave `$text`.
   Es el grueso: habilidades, stratagems, enhancements, efectos de detachment.

   ```json
   { "name": "Chaos Lord", "typeName": "Abilities",
     "characteristics": [
       { "name": "Description", "$text": "While this model is leading a unit, ...", "typeId": "…" }
     ] }
   ```

   Hay unas pocas characteristics más que también son prosa: `Descriptions`, `Capacity`, `Effect`,
   `Orders`, `Ability` y `Button Effect`.

2. **`description`** en `sharedRules[]` / `rules[]` → las reglas núcleo del juego, definidas
   una sola vez en `Warhammer 40,000.json` y referenciadas desde cualquier facción.

3. **`modifiers[].value`**, cuando el `field` del modifier apunta a una de esas characteristics de
   prosa: son reglas que reescriben la descripción de una habilidad, y ese texto también lo ve el
   jugador. Un modifier que escribe sobre `Keywords` o sobre `hidden`, en cambio, no se traduce.

Las demás `characteristics` (`Range`, `A`, `S`, `AP`, `D`, `BS`, `WS`, `M`, `T`, `Sv`, `W`,
`LD`, `OC`, `InSv`, `Keywords`) son estadísticas o listas de palabras clave: **no se traducen**.
Los campos `name` tampoco — son los nombres propios que se quedan en inglés. Los `comment` son
notas internas de los mantenedores de BSData y no llegan al jugador.

## Volumen medido sobre este snapshot

| Métrica | Valor |
|---|---|
| Textos traducibles (con repeticiones entre facciones) | 6.528 |
| Textos únicos a traducir | 5.662 |
| Nombres propios distintos (campos `name`) a proteger | 13.533 |
| Reglas núcleo en `sharedRules` del game system | 49 entradas / 37 definiciones únicas |

Las 49 entradas de `sharedRules` incluyen variantes que repiten definición (`Feel No Pain 4+`,
`5+`, `6+`… comparten texto; igual con `Scouts 5"`–`9"`). Al deduplicar quedan 37 definiciones
reales, que son el glosario de la pestaña Wiki.

## Cómo se lee este dataset para construir listas

Lo que la app tiene que implementar para convertir estos ficheros en un roster. Todo lo de aquí
está comprobado sobre el dato real; `audit` del pipeline lo verifica en cada refresco.

- **Los enlaces resuelven por id, y cruzan ficheros.** Hay 103.436 identificadores y 43.773
  referencias `targetId` (`entryLinks`, `categoryLinks`, `infoLinks`, `catalogueLinks`), y todas
  apuntan a algo existente. El índice tiene que construirse sobre los 46 ficheros a la vez, no por
  fichero.
- **La lista de unidades de una facción no está solo en su fichero.** Son sus `entryLinks` raíz más
  los del catálogo que enlace con `importRootEntries`. Sin resolver eso, White Scars, Iron Hands o
  Salamanders se quedan en **cero** unidades; con ello pasan a 65. Es lo que hace que cada capítulo
  de Space Marines funcione como facción propia.
- **El coste es la suma del árbol seleccionado, no un precio de la unidad.** Los `costs` van por
  `typeId` (el de puntos es `51b2-306e-1021-d207`) y pueden no estar en la unidad: en
  *Myphitic Blight-hauler*, por ejemplo, los 95 puntos están en la miniatura que cuelga de ella.
- **La legalidad se lee de `constraints`**: `type` (min/max) sobre un `field` (`selections`, un
  tipo de coste como Enhancements, o `associations`), con un `scope` que dice contra qué se cuenta
  (`self`, `parent`, `force`, `roster`, `root-entry`) y `includeChildSelections`. Ese es el
  intérprete de reglas del informe, y el dato ya trae el mensaje de error en `message`.
- **El rol en la lista sale de `categoryLinks`**, donde el que tiene `primary: true` es el rol
  principal de la unidad.
- **Seis unidades no tienen puntos y es correcto**: *Spore Mines*, *Mucolid Spores* y
  *Ripper Swarms* son gratuitas y llegan con otra unidad, y las dos fortificaciones marcadas
  `[Legends]` no están puntuadas. La app debe mostrarlas a 0, no tratarlo como un error.

Sobre el dataset actual eso da 36 facciones jugables y 1.381 unidades distintas.

## Actualizar desde upstream

```bash
git clone --depth 1 https://github.com/BSData/wh40k-11e.git /tmp/wh40k-11e
rm -f data/bsdata/*.json
cp /tmp/wh40k-11e/*.json data/bsdata/
```

Después hay que regenerar `SOURCE.json` con el nuevo commit y los nuevos `sha256`, y volver a
pasar el pipeline de traducción sobre los textos que hayan cambiado.
