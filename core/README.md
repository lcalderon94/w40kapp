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

## Construir una lista

```dart
final roster = Roster(faction: faccion, pointsLimit: 2000)
  ..detachment = dataset.detachmentsOf(faccion).first;
roster.add(dataset.selectionFor(unidad));      // la unidad con sus mínimos ya puestos
print('${roster.points}/${roster.pointsLimit}');
for (final incumplimiento in roster.validate()) print(incumplimiento);
```

`selectionFor` no añade la unidad suelta: despliega los mínimos que exige. Los Poxwalkers cuestan 65
en la unidad y llevan diez miniaturas a 0, y el Myphitic Blight-hauler cuesta 0 en la unidad y 95 en
la suya; sumando el árbol los dos salen bien.

Los **modifiers de coste** se aplican al recalcular: el dataset da 65 puntos a los Poxwalkers y deja
en un modifier que pasen a 130 al superar las diez miniaturas, así que sin evaluarlos una unidad de
veinte costaría lo mismo que una de diez.

`detachmentsOf` da los detachments de la facción con su regla ya traducida. Cuelgan de la entrada
de configuración, en un grupo que unas facciones llevan incrustado y otras enlazan, y las hereda
quien no los declara: por eso los capítulos de Space Marines tienen los cinco del codex. Resuelven
34 de las 36 facciones; Aeldari y Drukhari los declaran de otra forma que aún no se sigue.

`enhancementsOf` da las mejoras que habilita un detachment, con su texto traducido. Lo que
identifica a una mejora no es el coste del tipo Enhancements ni el nombre de su grupo —hay
facciones que no usan ese coste y otras que llaman al grupo de otra manera—, sino **estar atada a
un detachment**: es una opción con coste en puntos que el dataset esconde salvo que se haya elegido
ese detachment. El gate puede estar en la propia mejora o en cualquier nodo que la contenga, y las
mejoras pueden vivir en un catálogo enlazado.

Cubre 900 de los 936 detachments, y 662 dan exactamente las cuatro que corresponden en 11ª edición.
El criterio se queda corto antes que inventarse nada: **si devuelve una mejora, es de ese
detachment** —ninguna aparece en dos, y hay un test que lo comprueba—. Los 36 restantes no atan
ninguna mejora a su detachment en el dataset; `enhancementCoverage` dice de cuáles fiarse antes de
enseñar una lista vacía.

`validate` cubre el límite de puntos, que se haya elegido detachment, los mínimos y máximos de cada opción, los de su grupo —«entre
10 y 20 Poxwalkers», que se comprueban sumando los hermanos que salen del mismo grupo— y los que
limitan cuántas veces puede repetirse una unidad en el ejército. Cuando el dataset trae su propio
mensaje de error, se usa ese.

## Qué pasa cuando el motor no entiende una condición

No la aplica, y lo cuenta en `Roster.skippedModifiers`. Es deliberado: un precio calculado con una
condición mal interpretada parece correcto y no lo es, que en una app de listas es peor que
quedarse corto.

Hoy quedan fuera 1.816 modifiers de coste, que afectan al 27,8 % de las unidades. Todos son la
misma construcción, `localConditionGroups`: cuentan instancias repetidas de la misma unidad dentro
del padre (`atLeast` 1 a 3) con dos comparaciones propias, `before` e `instanceOf`. Como necesitan
una instancia previa para dispararse, **el precio de una lista sin unidades repetidas es exacto**;
la desviación aparece al meter varias copias de la misma unidad en un destacamento.

## Estado

Se lee el dataset, se construyen y validan listas, y se aplican los modifiers de coste evaluables.
Lo que falta para la paridad con WarOrgan:

- **`localConditionGroups`**, lo de arriba: implementarlos exige la semántica exacta de `before` e
  `instanceOf`, que conviene sacar de la especificación de BattleScribe y no deducirla.
- **Modifiers sobre restricciones**, que cambian los límites en vez del coste.
- **Las mejoras de 36 detachments** que el dataset no ata a ninguno; habría que mirarlos uno a uno
  o esperar a que upstream los complete.
- **Los detachments de Aeldari y Drukhari**, que no cuelgan de la entrada de configuración.
- **Límites por rol** del destacamento, que viven en las `categoryEntries` de `forceEntries`.

## Entorno

El contenedor de desarrollo no trae Dart. Para trabajar aquí:

```bash
curl -sSLo dartsdk.zip https://storage.googleapis.com/dart-archive/channels/stable/release/latest/sdk/dartsdk-linux-x64-release.zip
unzip -q dartsdk.zip && export PATH="$PWD/dart-sdk/bin:$PATH"
```
