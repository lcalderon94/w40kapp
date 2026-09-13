# pipeline — preparación de datos

Herramienta de línea de comandos (Spring Boot, Maven, Java 17) que prepara el dataset para la app.
**No forma parte de la app**: se ejecuta en local y su salida es lo que luego se empaqueta en Flutter.

Hace las tres cosas que no se pueden hacer a mano sobre 6.500 textos repartidos en 46 ficheros:
extraer lo traducible, deduplicarlo, y volver a inyectar las traducciones sin romper nada.

## Uso

Desde la raíz del repositorio:

```bash
mvn -f pipeline/pom.xml spring-boot:run -Dspring-boot.run.arguments=extract
mvn -f pipeline/pom.xml spring-boot:run "-Dspring-boot.run.arguments=import .entregas"
mvn -f pipeline/pom.xml spring-boot:run -Dspring-boot.run.arguments=check
mvn -f pipeline/pom.xml spring-boot:run -Dspring-boot.run.arguments=audit
mvn -f pipeline/pom.xml spring-boot:run -Dspring-boot.run.arguments=apply
mvn -f pipeline/pom.xml test
```

## El ciclo de trabajo

```
data/bsdata/  ──extract──▶  data/translations/es/batch-NNN.json  ──apply──▶  data/bsdata-es/
   (inglés,                        (se rellena el campo                    (generado, no se
    upstream)                       "target" traduciendo)                   versiona)
```

1. **`extract`** recorre los 46 ficheros, se queda con los textos traducibles, los deduplica y
   escribe lotes con lo que aún está pendiente. No toca los lotes que ya existen, así que se puede
   ejecutar tantas veces como haga falta.
2. **Traducir** consiste en rellenar el campo `target` de cada unidad del lote. Es el paso que se
   hace con Claude, lote a lote, siguiendo
   [`data/translations/GLOSARIO.md`](../data/translations/GLOSARIO.md).

3. **`import`** hace falta solo si se traduce en paralelo: en ese caso cada traductor entrega un
   fichero suelto de `{"id": "traducción"}` en vez de editar los lotes, y este comando los fusiona.
   Acepta ficheros o un directorio entero, e informa de cuántas traducciones aplica, cuántas
   sustituyen a una anterior y cuántas traen un id que ya no existe. Así varios traductores
   trabajando a la vez no se pisan entre ellos.
4. **`check`** revisa la memoria de traducción antes de aplicarla: avisa si una traducción ha
   perdido por el camino alguna keyword entre corchetes del original, o si quedó igual que el
   inglés. Termina con error si encuentra algo, para poder encadenarlo en un script.
5. **`apply`** reinyecta las traducciones y escribe el dataset en español. Los textos sin traducir
   se quedan en inglés, así que se puede ir aplicando a medio camino.

**`audit`** es aparte del ciclo de traducción: comprueba que el dataset siga sirviendo para
construir listas. Que toda referencia entre ficheros resuelva, que cada facción jugable resuelva su
lista de unidades —incluidas las que hereda por `importRootEntries`, sin las cuales los capítulos de
Space Marines se quedan a cero— y que cada unidad tenga coste en puntos en algún punto de su árbol.
Conviene pasarlo tras refrescar desde upstream: una referencia rota no se ve leyendo el JSON pero
deja la app inservible. Lo que comprueba está detallado en
[`data/README.md`](../data/README.md#cómo-se-lee-este-dataset-para-construir-listas).

`extract` informa además de cuántas unidades quedan huérfanas: traducciones cuyo texto original ya
no existe porque upstream lo cambió. No se borran solas.

### Formato de un lote

```json
{
  "batch": 29,
  "units": [
    {
      "id": "ec011ccdf1d74e8f",
      "kind": "rule",
      "occurrences": 1,
      "files": ["Warhammer 40,000"],
      "protect": { "keywords": ["[TORRENT]"], "names": ["Torrent"] },
      "source": "Each time an attack is made with a **[TORRENT]** weapon, ...",
      "target": "Cada vez que se realiza un ataque con un arma **[TORRENT]**, ..."
    }
  ]
}
```

- **`id`** es el hash del texto original. Es estable: si upstream reescribe una frase, cambia su id
  y vuelve a aparecer como pendiente, sin invalidar el resto de la traducción.
- **`occurrences`** dice en cuántos sitios aparece ese mismo texto. Traducirlo una vez lo resuelve
  en todos: por eso 6.528 textos son solo 5.662 unidades.
- **`protect`** es la lista de cosas que deben quedarse en inglés dentro de ese texto: las
  keywords entre corchetes y los nombres propios del dataset que aparecen en la frase.

Los lotes se versionan en el repositorio: son la memoria de traducción, no un fichero temporal.

## Qué se considera traducible

Se traduce la prosa que ve el jugador:

- `characteristics[]` cuyo `name` sea `Description`, `Descriptions`, `Capacity`, `Effect`,
  `Orders`, `Ability` o `Button Effect` → su clave `$text`
- `description` en `rules[]` y `sharedRules[]`
- `modifiers[].value` **solo** cuando su `field` apunta a una characteristic de las anteriores: hay
  modifiers que reescriben la descripción de una habilidad, y ese texto también lo ve el jugador

No se toca nada más. En concreto quedan fuera los campos `name` (nombres propios), las
characteristics de estadísticas (`M`, `T`, `Sv`, `W`, `A`, `S`, `AP`, `D`, `Range`, `BS`, `WS`,
`LD`, `OC`, `InSv`), las `Keywords`, los `comment` (notas internas de los mantenedores de BSData) y
los `affects` de los modifiers, que son expresiones de la lógica de reglas.

## Por qué la salida no se rompe

Los ficheros de BSData no usan un pretty-print estándar: los objetos hoja van en una sola línea.
Re-serializarlos con Jackson cambiaría el formato de las 48 MB enteras y haría el diff ilegible.

En vez de eso, el escaneo anota el **offset exacto** del literal de cada texto y `apply` sustituye
solo ese tramo del fichero original. La consecuencia es que el resultado es idéntico byte a byte
salvo en los textos traducidos, y la estructura y la lógica de BattleScribe no se pueden alterar por
accidente.

`DatasetRoundTripTest` lo verifica sobre los 46 ficheros reales: reemplaza cada literal por su
propio valor y exige que el fichero quede exactamente igual. Si algún día un cambio rompe el
cálculo de offsets, ese test falla antes de que se escriba nada.

## Configuración

Valores por defecto en `src/main/resources/application.yml`, sobreescribibles por línea de comandos:

| Propiedad | Por defecto | Qué es |
|---|---|---|
| `warorgan.source-dir` | `data/bsdata` | Dataset en inglés |
| `warorgan.spanish-dir` | `data/bsdata-es` | Salida traducida |
| `warorgan.translations-dir` | `data/translations/es` | Lotes de traducción |
| `warorgan.batch-chars` | `40000` | Caracteres de texto original por lote |
