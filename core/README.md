# core — capa de datos

Lee el dataset de BattleScribe ya traducido y lo resuelve en facciones, unidades y perfiles.

Es **Dart puro, sin Flutter**, a propósito: la parte difícil de esta app no es la interfaz sino
interpretar el dato, y así se puede probar contra el dataset real sin levantar nada. La app Flutter
dependerá de este paquete.

```bash
cd core
dart test                                  # pruebas contra el dataset real
dart run bin/resumen.dart                  # vuelca lo que resuelve, sin interfaz
dart run bin/resumen.dart ../data/bsdata-es "Imperium - Adeptus Astartes - White Scars"
```

Necesita el dataset en español generado (`apply` del pipeline). Si no está, las pruebas caen sobre
`data/bsdata` en inglés, que tiene la misma estructura.

## Qué resuelve

```dart
final dataset = await Dataset.load(Directory('data/bsdata-es'));
final faccion = dataset.factionNamed('Chaos - Death Guard');
for (final unidad in faccion.units) {
  print('${unidad.name}: ${unidad.points} pts, ${unidad.role}');
  for (final habilidad in unidad.abilities) {
    print('  ${habilidad.name}: ${habilidad.description}');
  }
}
```

Las tres cosas que hace y que no son evidentes leyendo el JSON:

- **Indexa los 46 ficheros juntos.** Se referencian entre ellos por identificador, así que una
  facción cargada por su cuenta no puede resolver nada.
- **Hereda las unidades de los catálogos enlazados** (`importRootEntries`). White Scars declara un
  puñado de personajes propios y saca del catálogo de Space Marines las más de cincuenta unidades
  restantes; sin resolver esa herencia la facción sería injugable.
- **Busca los puntos donde estén.** Unas unidades declaran su coste y otras lo dejan en la
  miniatura que cuelga de ellas, como el Myphitic Blight-hauler y sus 95 puntos.

`UnitEntry.points` es el coste de la configuración base, no el final: en el roster el coste es la
suma de todo lo seleccionado, y eso ya depende de las opciones del jugador. Esa parte, junto con la
evaluación de `constraints`, es del constructor de listas, no de esta capa.

## Estado

Cubre la lectura del dataset. Falta lo que va encima: construir un roster, sumar su coste y evaluar
las restricciones de legalidad. `Constraint` ya expone `type`, `field`, `scope` y el `message` que
trae el propio dataset, que es lo que necesita ese intérprete.

## Entorno

El contenedor de desarrollo no trae Dart. Para trabajar aquí:

```bash
curl -sSLo dartsdk.zip https://storage.googleapis.com/dart-archive/channels/stable/release/latest/sdk/dartsdk-linux-x64-release.zip
unzip -q dartsdk.zip && export PATH="$PWD/dart-sdk/bin:$PATH"
```
