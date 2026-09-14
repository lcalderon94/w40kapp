# app — la interfaz

La app de Android, en Flutter. Depende del paquete `core`, que es quien entiende el dataset; aquí
solo se pinta y se navega.

```bash
../tool/preparar-datos.sh   # deja el dataset en español en assets/ (no está en el repo)
flutter test                # pruebas de widget contra el dataset real
flutter run                 # en un dispositivo o emulador
```

## Qué hay

- **Listas** → crear una lista eligiendo facción y tamaño de partida, elegir detachment, añadir
  unidades y equiparlas. Arriba siempre: puntos, presupuesto de mejoras y si la lista es legal.
  Se guardan solas en el teléfono y se exportan a texto plano para pegarlas en un chat.
- **Ejércitos** → las 36 facciones agrupadas por bando → sus unidades, buscables → la ficha de cada
  una: línea de características, habilidades y armas con sus perfiles.
- **Wiki** → el glosario del reglamento básico, las 49 reglas que salen entre corchetes en las
  armas (**[SUSTAINED HITS]**, **[DEVASTATING WOUNDS]**, **[ANTI-INFANTRY 4+]**) y que hay que ir a
  buscar en mitad de una partida. Buscables por nombre y por texto.

## Decisiones que no se ven

**El tamaño de partida se elige lo primero, con la facción.** No es solo el límite de puntos:
cambia las reglas. En Incursion la mayoría de las unidades solo se pueden repetir dos veces y caben
dos mejoras en vez de cuatro, así que elegirlo al final obligaría a rehacer la lista.

**El detachment va antes que las unidades** por lo mismo, y además decide **qué unidades hay**: los
demonios de Nurgle solo entran en una lista de Death Guard si llevas Tallyband Summoners. Por eso la
pantalla de elegirlo enseña la regla entera y las mejoras que habilita.

**El selector solo ofrece lo que la lista puede llevar.** Un catálogo trae mucho más que su facción
—Legends, aliados, fortificaciones—, y de las 6.149 unidades del dataset una lista puede llevar
2.068. Lo que se puede añadir a mano se enciende con el botón de arriba del selector: son los
interruptores del propio dataset, apagados por defecto.

**Una unidad recién añadida casi siempre avisa, y está bien.** 3.019 de las 6.149 exigen elegir un
arma o un tamaño de escuadra, y nadie puede decidirlo por el jugador. La lista marca *en qué unidad*
está el problema, porque «tu lista tiene 4 avisos» sin decir cuál abrir no sirve de nada.

**Se guarda solo, sin botón.** Una app de listas que te pierde el trabajo por no haber pulsado
«guardar» no la usa nadie dos veces, así que `ListaEnCurso` avisa de cada cambio y eso escribe. Y se
guardan las *decisiones*, no el árbol: al abrir la app la lista se vuelve a montar contra el
dataset, así que sale con los puntos de hoy en vez de con los de cuando se guardó.

**Nadie recalcula nada aquí.** `ListaEnCurso` envuelve al `Roster` del `core` y solo traduce «el
jugador ha tocado algo» a «hay que volver a pintar». El precio, los presupuestos y la legalidad los
sabe el motor, y todo lo que cambia la lista pasa por un único sitio: no hay forma de mover una
pieza sin que se recalcule.

**Los datos van dentro.** Son 46 ficheros que se referencian entre ellos, así que se cargan todos
de golpe al arrancar: no se puede cargar media facción. Tarda un par de segundos largos y por eso
hay pantalla de carga, que es preferible a fingir que la app ya está lista. A cambio funciona sin
conexión, que en un torneo no es un lujo.

**El texto del dataset trae marcas.** BattleScribe escribe `**negrita**` y `^^palabra clave^^`, y
las anida. `trozosDeRegla` las resuelve con dos interruptores en vez de con un analizador: no hay
estructura que entender, solo marcas que se abren y se cierran, y así una marca suelta —que las
hay— degrada a texto normal en vez de romper la ficha.

**Las armas no cuelgan de la unidad.** Viven en las opciones de sus miniaturas, un par de niveles
más abajo, y juntarlas es interpretar el dataset, no pintarlo: lo hace `Dataset.sheetOf` en el
`core`, donde se puede probar sin levantar una interfaz.

## Lo que falta

**El arranque.** Son 48 MB y 103.000 nodos que hay que indexar antes de resolver nada, y se hace en
el hilo de la interfaz. Aquí son un par de segundos; en un móvil de gama media serán más, y el
siguiente paso es moverlo a un isolate.
