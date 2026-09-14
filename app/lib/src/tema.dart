import 'package:flutter/material.dart';

/// El aspecto de la app: oscuro, sobrio y con un solo acento.
///
/// Oscuro porque se usa en una mesa de juego y a veces con poca luz, y sobrio porque el contenido
/// ya es denso de por sí —líneas de características, listas de reglas— y no aguanta competencia.
/// El acento es hueso viejo: marca lo que se puede tocar y lo que hay que leer, y nada más.
abstract final class Tema {
  static const fondo = Color(0xFF121110);
  static const superficie = Color(0xFF1C1A18);
  static const superficieAlta = Color(0xFF262320);
  static const acento = Color(0xFFC8A265);
  static const texto = Color(0xFFE8E4DE);
  static const textoTenue = Color(0xFF9A938A);
  static const aviso = Color(0xFFD1656B);

  static ThemeData get oscuro {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: fondo,
      colorScheme: base.colorScheme.copyWith(
        primary: acento,
        surface: superficie,
        onSurface: texto,
        error: aviso,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: fondo,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: texto,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF2E2A26), space: 1, thickness: 1),
      textTheme: base.textTheme.apply(bodyColor: texto, displayColor: texto),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: superficie,
        hintStyle: const TextStyle(color: textoTenue),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  /// Estilo de las palabras clave del reglamento, las que van entre `^^` en el dataset.
  static const clave = TextStyle(
    color: acento,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
  );
}
