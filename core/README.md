# core — capa de datos

Lee el dataset de BattleScribe ya traducido y lo resuelve en facciones, unidades y perfiles.

Es **Dart puro, sin Flutter**, a propósito: la parte difícil de esta app no es la interfaz sino
interpretar el dato, y así se puede probar contra el dataset real sin levantar nada. La app Flutter
dependerá de este paquete.

```bash
cd core
dart test                                  # pruebas contra el dataset real
dart run bin/auditoria.dart                # cuánto del dataset entiende el motor
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
final tamano = dataset.battleSizes.firstWhere((b) => b.pointsLimit == 2000);
final roster = Roster(faction: faccion, pointsLimit: tamano.pointsLimit)
  ..detachment = dataset.detachmentsOf(faccion).first
  ..battleSize = tamano;
roster.add(dataset.selectionFor(unidad));      // la unidad con sus mínimos ya puestos
print('${roster.points}/${roster.pointsLimit}');
for (final incumplimiento in roster.validate()) print(incumplimiento);
```

`selectionFor` no añade la unidad suelta: despliega los mínimos que exige. Los Poxwalkers cuestan 65
en la unidad y llevan diez miniaturas a 0, y el Myphitic Blight-hauler cuesta 0 en la unidad y 95 en
la suya; sumando el árbol los dos salen bien.

`optionsFor` da lo otro, lo que se elige: las armas, el equipo y también las **mejoras**, que no son
un caso aparte sino un grupo más de los que cuelgan de un personaje. Cada opción viene construida y
lista para `addChild`, con sus costes y sus restricciones, así que valida y suma igual que lo que
salió del mínimo.

Deja fuera el material de **Crusade**, que el dataset mete en todas las unidades sin marcarlo de
ninguna manera: no lo esconde con un modifier, no lo mete en una categoría propia y no lo ata al
tipo de fuerza. Como no hay señal que seguir, el criterio lo pone esta capa: se reconoce por su
coste —hay cuatro tipos de coste que solo existen en Crusade— y, cuando no cuesta nada, por el
nombre de su sección. Se comprobó sobre el dataset entero antes de aplicarlo: de lo que esconde,
**nada cuesta puntos y nada es una mejora**. Con `crusade: true` vuelve. El filtro quita el 87 % de
las opciones ofrecidas, de un millón largo a 139.254, que es la diferencia entre una pantalla de
equipo legible y una lista de la compra.

```dart
final principe = dataset.selectionFor(unidad);
final mejora = dataset.optionsFor(principe).firstWhere((o) => o.groupName == 'Enhancements');
principe.addChild(mejora);   // +10 pts y una Enhancement gastada del presupuesto
```

Los **modifiers de coste** se aplican al recalcular: el dataset da 65 puntos a los Poxwalkers y deja
en un modifier que pasen a 130 al superar las diez miniaturas, así que sin evaluarlos una unidad de
veinte costaría lo mismo que una de diez.

`detachmentsOf` da los detachments de la facción con su regla ya traducida, y resuelve las 36. Los
declara la entrada de configuración, en un grupo que unas facciones llevan incrustado y otras
enlazan, y los hereda quien no los declara: por eso los capítulos de Space Marines tienen los del
codex común.

Un mismo grupo puede servir a **varias facciones a la vez**, y entonces no todo lo que contiene es
de todas: los veinticuatro de la librería de Aeldari se reparten entre Aeldari (15) y Drukhari (9),
y los cincuenta y ocho del codex de Space Marines entre los doce capítulos. Lo que los separa es un
modifier que esconde cada uno según cuál sea el catálogo principal, así que **hay que evaluarlo**:
sin hacerlo los Ultramarines ofrecerían el Inner Circle Task Force de los Dark Angels. Son
condiciones `instanceOf` y `notInstanceOf` sobre `primary-catalogue`, las dos documentadas, y
ninguna de las 265 opciones de detachment las mete en un grupo, así que cada una decide por sí sola.

El mismo grupo mezcla además los dos **modos de juego**, y los reparte igual pero con ámbito
`force`: los normales se esconden en Boarding Actions y los quince del modo se esconden fuera de
él. `detachmentsOf` da los de una partida normal, y con `boardingActions: true` los del modo.

### Qué unidades puede llevar una lista

`Roster.availableUnits`, no `Faction.units`. Un catálogo trae **mucho más que su facción**: un
ejército de Imperial Knights son sus veintitrés Knights, no las ciento tres entradas del fichero, y
el resto son aliados, Legends y fortificaciones. Sobre las 6.149 unidades del dataset, una lista
puede llevar **2.068**.

Lo decide el dataset con modifiers `hidden`, que llevan **el 76,7 % de las unidades**, y de dos
maneras:

- **Interruptores de contenido.** «Show Legends», «Show Imperial Agents», «Show Nurgle Daemons»…
  Son entradas de configuración apagadas por defecto, y van **por facción**: cuelgan del enlace de
  cada catálogo, así que Chaos Daemons trae uno por dios y Astra Militarum los Imperial Agents. Se
  piden con `visibilityOptionsOf` y se encienden en `Roster.shownOptions`.
- **Condiciones sobre la propia lista.** El detachment elegido, el tamaño de partida, el tipo de
  fuerza y la facción. Es lo que dice que los Plaguebearers de una lista de Death Guard piden
  Tallyband Summoners: sin evaluarlo, el selector los ofrece con cualquier detachment y la lista se
  da por buena sin serlo.

Hay un test que lo comprueba **en las 36 facciones a la vez**, no en una: 29 de ellas atan unidades
a un detachment y son **301 casos** —los demonios de cada dios en las cuatro legiones del Caos, los
Ynnari de Aeldari, los Tyránidos aliados de Genestealer Cults, los cultistas de Chaos Knights, los
Corsarios de Drukhari—. Y no da por hecho la dirección del gate: el dataset lo usa para enseñar
unidades y también para esconderlas. Lo que exige es que elegir ese detachment cambie lo que se
ofrece. Pasan los 301.

Cuando una condición no se sabe evaluar **no se esconde** y se cuenta en
`Roster.unresolvedVisibility`. Hoy es **cero**.

`enhancementsOf` da las mejoras que habilita un detachment, con su texto traducido. Lo que
identifica a una mejora no es el coste del tipo Enhancements ni el nombre de su grupo —hay
facciones que no usan ese coste y otras que llaman al grupo de otra manera—, sino **estar atada a
un detachment**: es una opción con coste en puntos que el dataset esconde salvo que se haya elegido
ese detachment. El gate puede estar en la propia mejora o en cualquier nodo que la contenga, y las
mejoras pueden vivir en un catálogo enlazado.

Cubre **546 de los 547** detachments jugables; el único que se queda fuera es el Contagion Engines
de la Death Guard. El dataset los gradúa por Detachment Points, y sobre los de tamaño completo —los
de 2 y 3 puntos— la resolución es exacta: **377 de 378 dan las cuatro mejoras** que corresponden en
11ª edición, y la excepción es el Lords of Dread de los Chaos Knights, que devuelve seis. Los de 1
punto son los pequeños y llevan una o dos por diseño, no por quedarse corto el criterio.

El criterio se queda corto antes que inventarse nada: **si devuelve una mejora, es de ese
detachment** —ninguna aparece en dos, y hay un test que lo comprueba—. `enhancementCoverage` dice
de cuáles fiarse antes de enseñar una lista vacía.

`validate` cubre el límite de puntos, que se haya elegido detachment, los mínimos y máximos de cada
opción, los de su grupo —«entre 10 y 20 Poxwalkers», que se comprueban sumando los hermanos que
salen del mismo grupo— y los que limitan cuántas veces puede repetirse una unidad en el ejército.

Los grupos se comprueban **aunque estén vacíos**, que es justo cuando incumplen: mirando solo los
que ya tienen algo dentro, unos Blightlord Terminators sin ninguna miniatura elegida salían legales
con su grupo de «entre 2 y 9» a cero. Por eso **3.019 de las 6.149 unidades avisan nada más
añadirlas**: el dataset exige elegir un arma o un tamaño de escuadra y nadie puede decidirlo por el
jugador. Cuando el grupo ofrece una sola opción sí se rellena solo, que ahí no hay nada que elegir.

Y los cubre con el **límite efectivo, no con el declarado**, que rara vez son el mismo número. Hay
2.533 modifiers que cambian una restricción de selecciones, y la mitad larga miran el tamaño de la
partida: 4.544 de las 6.149 unidades se pueden repetir tres veces en Strike Force y solo dos en
Incursion. Es la regla de las tres copias escalada por tamaño, y el dataset la escribe como un
`set 2` sobre la restricción, no dentro de ella. Sin aplicarlo, una lista de 1000 puntos se valida
con los límites de una de 2000.

Por eso el roster necesita saber **de qué partida se trata**:

- `battleSize`, uno de los tres que da `dataset.battleSizes`, cada uno con su límite de puntos
  sacado del propio dataset. Sin él esos límites no se comprueban: contestar «no es Incursion» sin
  saberlo dejaría puesto el límite grande en una lista que a lo mejor es pequeña.
- `force`, el tipo de lista. Por defecto Army Roster, la partida normal. En Crusade el máximo de
  Poxwalkers se dobla a seis, y quien lo dice es una condición `instanceOf` sobre el tipo de
  fuerza: en general `instanceOf` pregunta si una selección desciende de una entrada y no se sabe
  contestar, pero los tipos de fuerza son cuatro y una lista es de uno solo, así que ahí sí.

También cuentan los ajustes que vienen **por el enlace**. Una entrada compartida no se usa igual en
todas partes, y el enlace es donde el dataset la ajusta a su sitio: trae sus propias restricciones y
sus propios modifiers. Vale para las entradas y para los grupos: «Heavy Weapons» es un grupo que
comparten varios tanques, y cuántas armas caben en cada uno lo dice su enlace.

Y cuentan las **proporciones**, que es como el dataset escribe «una Bright Lance menos por cada
Starcannon» o «un no-Battleline de Khorne más por cada Battleline». Son 5.499 modifiers con
`repeats`; sin ellas el cambio se aplica una sola vez y el límite se queda corto en cuanto la
unidad crece.

### Las reglas del ejército entero

No son de ninguna unidad: las declara el tipo de fuerza, y se leen del dataset en vez de escribirse
a mano, así que un cambio de upstream se sigue solo.

| Regla | Incursion | Strike Force | Onslaught |
|---|---|---|---|
| Límite de puntos | 1000 | 2000 | 3000 |
| Detachment Points | 2 | 3 | 4 |
| Enhancements | 2 | 4 | 4 |

Los **Detachment Points** son el presupuesto de detachments, y por eso `Roster.detachments` es una
lista y no uno solo: el dataset deja el grupo en «mínimo 1, sin máximo» y lo que de verdad limita es
el presupuesto. Los detachments de partida normal gastan 2 o 3, así que en Onslaught caben dos.

Cuando el dataset trae su propio mensaje de error se usa ese, salvo si el límite efectivo ha
cambiado: el mensaje lleva el número declarado escrito dentro y diría otra cosa que el aviso.

## Qué pasa cuando el motor no entiende una condición

No la aplica, y lo cuenta en `Roster.skippedModifiers`. Es deliberado: un precio calculado con una
condición mal interpretada parece correcto y no lo es, que en una app de listas es peor que
quedarse corto.

Con las restricciones hace lo mismo: si no sabe calcular el límite efectivo, **no comprueba la
restricción** en vez de comprobarla contra el número declarado. Dar por ilegal una lista que no lo
es sería peor que no avisar. Queda contado en `Roster.uncheckedConstraints`, y
`selectionsWithUncheckedConstraints` dice en qué selecciones. Son 542, en el 8,6 % de las unidades,
y **354 de ellas** por condiciones que cuentan **fuerzas** —cuántos destacamentos de tal tipo hay en
el roster—, que esta capa no modela porque solo maneja una. La cifra subió de 65 al empezar a mirar
los grupos vacíos: no es que se evalúe peor, es que antes ni se miraban.

En el coste quedan fuera 1.838 modifiers, que afectan al 28,2 % de las unidades. Todos son la misma
construcción, `localConditionGroups`: cuentan instancias repetidas de la misma unidad dentro del
padre (`atLeast` 1 a 3) con dos comparaciones propias, `before` e `instanceOf`.

**No se implementan porque no existe especificación.** `localConditionGroup` no aparece en ningún
esquema publicado de BattleScribe: ni en el [2.03][esquema] que el propio dataset declara usar, ni
en `vNext`. Su condición interna `before` tampoco está en la lista oficial de tipos, que es
`lessThan`, `greaterThan`, `equalTo`, `notEqualTo`, `atLeast`, `atMost`, `instanceOf` y
`notInstanceOf`. Es una extensión que BSData ya usa y que no está documentada, así que
implementarla sería deducir su semántica del propio dato, que es justo como se calcula mal un
precio sin enterarse.

Como todas esas condiciones cuentan instancias anteriores, no pueden dispararse con una sola copia:
**el precio de una lista sin unidades repetidas es exacto**. Cuando las hay,
`Roster.selectionsWithUnresolvedCost` dice qué unidades concretas pueden quedarse cortas, para
avisar en ellas y no sobre la lista entera.

[esquema]: https://github.com/BSData/schemas/blob/master/src/xml/schema/v2_03/Catalogue.xsd

## Estado

`dart run bin/auditoria.dart` lo mide contra el dataset entero y es la respuesta corta:

```
facciones 36 · unidades 6.149 (98,3 % con puntos) · detachments 547 · opciones 139.254
unidades que una lista ofrece     2.056 de 6.149 (33,4 %)
mejoras                       546 de 547 detachments  ·  377 de 378 de tamaño completo dan 4
modifiers de coste sin evaluar    1.414, en el 23,0 % de las unidades
restricciones sin comprobar         118, en el  1,8 % de las unidades
visibilidad sin evaluar                 0
piden elegir algo al añadirse     3.019, en el 49,1 % de las unidades
```

Se lee el dataset, se eligen unidades y opciones, y se validan listas con los límites efectivos.
Lo que falta:

- **`localConditionGroups`**, lo de arriba: es todo el 28,2 %, y está bloqueado hasta que BSData
  publique el esquema. Solo afecta a listas con **copias repetidas de la misma unidad**; sin
  repetir, el precio es exacto.
- **Varias fuerzas en un roster**, para aliados y para Boarding Actions completo. Contar fuerzas ya
  se contesta —una lista es una fuerza de un tipo conocido—, así que lo que falta es poder tener
  más de una.
- **Las seis mejoras del Lords of Dread**, el único detachment de tamaño completo que no da cuatro,
  y el **Contagion Engines**, el único sin ninguna.
- **Límites por rol**: en 11ª prácticamente no existen. La fuerza declara uno (mínimo 1 Character)
  y el propio dataset lo desactiva con un modifier. Lo que sí existe son las reglas de ejército de
  arriba, que sí se comprueban.

## Entorno

El contenedor de desarrollo no trae Dart. Para trabajar aquí:

```bash
curl -sSLo dartsdk.zip https://storage.googleapis.com/dart-archive/channels/stable/release/latest/sdk/dartsdk-linux-x64-release.zip
unzip -q dartsdk.zip && export PATH="$PWD/dart-sdk/bin:$PATH"
```
