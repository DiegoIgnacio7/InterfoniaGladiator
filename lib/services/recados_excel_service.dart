import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

class RecadosExcelService {
  static DateTime? fechaLocal(dynamic valor) {
    final parsed = DateTime.tryParse(valor?.toString() ?? '');
    if (parsed == null) return null;
    // El servidor devuelve fechas UTC sin sufijo de zona horaria.
    return (parsed.isUtc
            ? parsed
            : DateTime.utc(
                parsed.year,
                parsed.month,
                parsed.day,
                parsed.hour,
                parsed.minute,
                parsed.second,
                parsed.millisecond,
                parsed.microsecond))
        .toLocal();
  }

  static Uint8List generar(List<Map<String, dynamic>> recados) {
    if (recados.isEmpty) {
      throw ArgumentError('No hay recados para exportar.');
    }
    final libro = Excel.createExcel();
    libro.rename('Sheet1', 'Recados');
    final hoja = libro['Recados'];
    const columnas = [
      'Departamento',
      'RUT del emisor',
      'Título',
      'Descripción',
      'Estado',
      'Fecha de creación',
      'Fecha de resolución',
    ];
    hoja.appendRow(columnas.map((s) => TextCellValue(s)).toList());
    const anchos = [18.0, 22.0, 36.0, 70.0, 16.0, 24.0, 24.0];
    for (var col = 0; col < columnas.length; col++) {
      hoja.setColumnWidth(col, anchos[col]);
      hoja
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
          .cellStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: ExcelColor.fromHexString('#5983B0'),
      );
    }
    hoja.setRowHeight(0, 26);
    CellValue? fecha(dynamic valor) {
      final local = fechaLocal(valor);
      return local == null ? null : DateTimeCellValue.fromDateTime(local);
    }

    for (final recado in recados) {
      final rutEmisor = recado['rut_emisor']?.toString().trim() ?? '';
      // TextCellValue conserva identificadores y evita interpretar fórmulas.
      hoja.appendRow([
        TextCellValue(recado['id_dpto']?.toString() ?? ''),
        TextCellValue(rutEmisor.isEmpty ? 'No registrado' : rutEmisor),
        TextCellValue(recado['titulo']?.toString() ?? ''),
        TextCellValue(recado['descripcion']?.toString() ?? ''),
        TextCellValue(switch (recado['estado']) {
          'pendiente' => 'Pendiente',
          'resuelto' => 'Resuelto',
          final valor => valor?.toString() ?? '',
        }),
        fecha(recado['fecha_creacion']),
        fecha(recado['fecha_resolucion']),
      ]);
      final fila = hoja.maxRows - 1;
      for (var col = 0; col < columnas.length; col++) {
        hoja
            .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: fila))
            .cellStyle = CellStyle(
          bold: true,
          fontColorHex: ExcelColor.white,
          backgroundColorHex: ExcelColor.fromHexString(
              recado['estado'] == 'resuelto' ? '#3FAF46' : '#C9211E'),
          verticalAlign: VerticalAlign.Top,
          textWrapping: TextWrapping.WrapText,
          numberFormat: col >= 5
              ? NumFormat.custom(formatCode: 'dd/mm/yyyy hh:mm')
              : NumFormat.standard_0,
        );
      }
    }
    final bytes = libro.encode();
    if (bytes == null || bytes.isEmpty) {
      throw StateError('No se pudo generar el archivo Excel.');
    }
    return Uint8List.fromList(bytes);
  }

  /// Devuelve false si el usuario cancela el selector de guardado.
  static Future<bool> exportar(List<Map<String, dynamic>> recados,
      {required bool resueltos}) async {
    final bytes = generar(recados);
    final fecha = DateTime.now().toIso8601String().replaceAll(':', '-');
    final nombre =
        'recados_${resueltos ? 'resueltos' : 'pendientes'}_$fecha.xlsx';
    final destino = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar recados en Excel',
      fileName: nombre,
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      bytes: bytes,
    );
    if (destino == null) return false;
    return true;
  }
}
