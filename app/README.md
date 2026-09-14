# app — la interfaz

La app de Android, en Flutter. Depende del paquete `core`, que es quien entiende el dataset; aquí
solo se pinta y se navega.

```bash
../tool/preparar-datos.sh   # deja el dataset en español en assets/ (no está en el repo)
flutter test                # pruebas de widget contra el dataset real
flutter run                 # en un dispositivo o emulador
```

## Qué hay

- **Ejércitos** → las 36 facciones agrupadas por bando → sus unidades, buscables → la ficha de cada
  una: línea de características, habilidades y armas con sus perfiles.
- **Wiki** → el glosario del reglamento básico, las 49 reglas que salen entre corchetes en las
  armas (**[SUSTAINED HITS]**, **[DEVASTATING WOUNDS]**, **[ANTI-INFANTRY 4+]**) y que hay que ir a
  buscar en mitad de una partida. Buscables por nombre y por texto.

## Decisiones que no se ven

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

El constructor de listas. El `core` ya lo resuelve entero —elegir detachment, unidades y opciones,
sumar puntos y validar la lista contra las reglas del ejército—, pero todavía no tiene pantallas.
