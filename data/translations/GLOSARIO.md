# Glosario y criterio de traducción

Referencia obligatoria al rellenar el campo `target` de los lotes. Existe para que 5.662 unidades
traducidas en tandas distintas suenen a un solo traductor y no a diez.

## La regla

**Se queda en inglés** lo que el jugador dice en inglés en la mesa y lo que la app va a enlazar
como término:

- Keywords entre corchetes: `[SUSTAINED HITS 2]`, `[LETHAL HITS]`, `[PISTOL]`, `[TORRENT]`
- Palabras clave en versalitas: `MONSTER/VEHICLE`, `CHARACTER`, `TITANIC`, `MOBILE`, `FLY`,
  `TRANSPORT`, `DEDICATED TRANSPORT`, `FORTIFICATION`, y los nombres de unidad en mayúsculas
- Nombres propios: unidades, personajes, armas, Stratagems, Detachments, Enhancements
- **Nombres de reglas y mecánicas con nombre propio**: Deep Strike, Stealth, Feel No Pain, Scouts,
  Lone Operative, Fights First, Deadly Demise, Damaged, Firing Deck, Crucible, Psychic Fortitude,
  Battle-shock, Marked for Greatness, Desperate Escape, Leadership, Rapid Ingress, Teleport Homer
- Siglas de características y recursos: `M`, `T`, `Sv`, `W`, `LD`, `OC`, `A`, `S`, `AP`, `D`, `BS`,
  `WS`, `CP`, `XP`, `D6`, `D3`

**Se traduce** todo lo demás, incluida la terminología de reglas escrita como prosa corriente.

## Terminología fija

| Inglés | Español |
|---|---|
| hit roll | tirada para impactar |
| wound roll | tirada para herir |
| Charge roll | tirada de carga |
| Advance roll | tirada de avance |
| critical hit / critical wound | impacto crítico / herida crítica |
| mortal wound | herida mortal |
| attack dice | dados de ataque |
| invulnerable save | salvación invulnerable |
| benefit of cover | beneficio de cobertura |
| Engagement Range | alcance de combate |
| normal / advance / fall-back move | movimiento normal / de avance / de repliegue |
| charge move | movimiento de carga |
| scout move | movimiento de exploración |
| ingress move | movimiento de entrada |
| emergency disembark move | movimiento de desembarco de emergencia |
| deployment zone | zona de despliegue |
| battlefield | campo de batalla |
| battle round | ronda de batalla |
| model / unit | miniatura / unidad |
| bearer | portador |
| attached unit | unidad adjunta |
| leader / support / bodyguard unit | unidad líder / de apoyo / de guardaespaldas |
| strategic reserves | reservas estratégicas |
| terrain features | elementos de escenografía |
| dense terrain features | elementos de escenografía densa |
| transport capacity | capacidad de transporte |
| to disembark / embarked | desembarcar / embarcada |
| eligible to shoot / to declare a charge | elegible para disparar / para declarar una carga |
| set up (a unit) | desplegar |
| destroyed | destruida |
| visible / fully visible | visible / completamente visible |
| Wounds characteristic | característica de Heridas |
| Move characteristic | característica de Movimiento |
| Objective Control characteristic | característica de Control de Objetivos |
| Armour Penetration characteristic | característica de Penetración de Blindaje |
| Designer's Note | Nota del diseñador |
| Example | Ejemplo |

## Forma

- **Respeta el marcado del original tal cual**: `**negrita**`, `***Ejemplo:** …*`, `^^…^^`, las
  viñetas (`-`, `■`), la numeración y los saltos de línea. El marcado se traduce con el texto que
  envuelve, no se mueve ni se añade.
- Conserva las referencias numéricas de sección: `(10.06)`, `(13.08)`.
- Conserva las comillas de pulgadas: `6"`, `12"`.
- Registro impersonal, en presente, tuteando al jugador como hace el original: «cada vez que…»,
  «puedes repetir…», «suma 1 a…».
- Traducción de reglas, no literal: prima que la regla se entienda y se aplique igual que en
  inglés. *Sustained Hits* nunca es «acoplado».

## Verificación

`check` comprueba que ninguna traducción pierda una keyword entre corchetes del original y avisa
si un nombre de regla del glosario ha desaparecido en la traducción:

```bash
mvn -f pipeline/pom.xml spring-boot:run -Dspring-boot.run.arguments=check
```
