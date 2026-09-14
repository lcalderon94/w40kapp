import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warorgan/src/tema.dart';
import 'package:warorgan/src/widgets/texto_reglas.dart';

void main() {
  const base = TextStyle(fontSize: 14);
  String texto(List<InlineSpan> trozos) =>
      trozos.map((t) => (t as TextSpan).text).join();
  List<TextSpan> spans(String origen) =>
      trozosDeRegla(origen, base).cast<TextSpan>();

  test('el texto sin marcas sale entero y sin tocar', () {
    final trozos = spans('Cada vez que una unidad es seleccionada para disparar.');
    expect(texto(trozos), 'Cada vez que una unidad es seleccionada para disparar.');
    expect(trozos.single.style, base);
  });

  test('lo que va entre ** sale en negrita', () {
    final trozos = spans('produce una **herida crítica** y termina');
    expect(texto(trozos), 'produce una herida crítica y termina');
    final negrita = trozos.firstWhere((t) => t.text == 'herida crítica');
    expect(negrita.style!.fontWeight, FontWeight.w700);
  });

  test('lo que va entre ^^ sale como palabra clave', () {
    final trozos = spans('contra una unidad ^^Vehicle^^ produce');
    final clave = trozos.firstWhere((t) => t.text == 'Vehicle');
    expect(clave.style!.color, Tema.acento);
  });

  test('las marcas se anidan, que es como vienen en el dataset', () {
    // El dataset escribe literalmente `^^**Vehicle**^^`.
    final trozos = spans('una unidad ^^**Vehicle**^^ enemiga');
    expect(texto(trozos), 'una unidad Vehicle enemiga');
    expect(trozos.firstWhere((t) => t.text == 'Vehicle').style!.color, Tema.acento);
  });

  test('una marca sin cerrar no rompe el texto', () {
    // Pasa en el dataset, y una ficha a medias es peor que una sin negrita.
    final trozos = spans('texto **sin cerrar');
    expect(texto(trozos), 'texto sin cerrar');
  });

  test('se quitan las etiquetas <ins>', () {
    expect(texto(spans('un <ins>añadido</ins> del dataset')), 'un añadido del dataset');
  });

  test('el texto vacío no da trozos', () {
    expect(spans(''), isEmpty);
  });
}
