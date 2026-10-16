import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../services/historial_excel_service.dart';

class HistorialModal extends StatefulWidget {
  final String miRut;
  final http.Client? client;
  const HistorialModal({super.key, required this.miRut, this.client});

  @override
  State<HistorialModal> createState() => _HistorialModalState();
}

class _HistorialModalState extends State<HistorialModal> {
  late final http.Client _client;
  List<Map<String, dynamic>> _historial = [];
  Map<String, String> _nombresPorRut = {};
  bool _loading = true;
  bool _exportando = false;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? http.Client();
    _cargar();
  }

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final res = await _client
          .get(
            Uri.parse('$kBaseUrl/historial')
                .replace(queryParameters: {'rut': widget.miRut}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        throw const FormatException('No se pudo consultar el historial.');
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! List || data.any((llamada) => llamada is! Map)) {
        throw const FormatException('El historial no es válido.');
      }
      final historial = data
          .map((llamada) => Map<String, dynamic>.from(llamada as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _historial = historial;
        _loading = false;
      });
      if (_requiereNombresParticipantes(historial)) {
        await _cargarNombresParticipantes();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _requiereNombresParticipantes(List<Map<String, dynamic>> historial) {
    String texto(dynamic valor) => valor?.toString().trim() ?? '';
    return historial.any((llamada) {
      final tipo =
          texto(llamada['tipo']).replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
      final saliente = tipo == 'saliente' || tipo.startsWith('saliente ');
      final faltaEmisor = texto(llamada['nombre_emisor']).isEmpty &&
          (texto(llamada['rut_emisor']).isNotEmpty ||
              (saliente && widget.miRut.trim().isNotEmpty));
      final faltaReceptor = texto(llamada['nombre_receptor']).isEmpty &&
          texto(llamada['rut_receptor']).isNotEmpty;
      return faltaEmisor || faltaReceptor;
    });
  }

  Future<void> _cargarNombresParticipantes() async {
    try {
      final nombres = await HistorialExcelService.consultarNombresParticipantes(
          _client, widget.miRut);
      if (!mounted) return;
      setState(() => _nombresPorRut = nombres);
    } catch (_) {
      // El historial permanece visible si no se puede consultar el directorio.
      // No se asigna al usuario actual como receptor de llamadas de terceros.
    }
  }

  Future<void> _exportarExcel() async {
    if (_loading || _exportando || _historial.isEmpty) return;
    final historial = List<Map<String, dynamic>>.from(_historial);
    setState(() => _exportando = true);
    try {
      final guardado = await HistorialExcelService.exportar(historial);
      if (guardado && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Excel guardado con ${historial.length} llamadas.'),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo guardar el Excel. Inténtalo nuevamente.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'finalizada':
        return const Color(0xFF4CAF50);
      case 'ocupado':
        return const Color(0xFFffb142);
      case 'perdida':
        return const Color(0xFFff5252);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF11111B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text('Historial de Llamadas',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w300)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('exportar_historial'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF20CDFF),
                    disabledForegroundColor: Colors.white38,
                  ),
                  onPressed: _loading || _exportando || _historial.isEmpty
                      ? null
                      : _exportarExcel,
                  icon: _exportando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined),
                  label: Text(_exportando
                      ? 'Guardando Excel…'
                      : 'Exportar a Excel (${_historial.length})'),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFF448AFF)))
                  : _historial.isEmpty
                      ? const Center(
                          child: Text('No hay historial de llamadas.',
                              style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _historial.length,
                          itemBuilder: (_, i) {
                            final l = _historial[i];
                            final participantes =
                                HistorialExcelService.resolverParticipantes(
                              l,
                              miRut: widget.miRut,
                              nombresPorRut: _nombresPorRut,
                            );
                            final tipo = (l['tipo'] ?? 'Llamada').toString();
                            final fecha =
                                HistorialExcelService.formatearFechaLocal(
                                    l['fecha']);
                            final estado =
                                (l['estado'] ?? 'Finalizada').toString();
                            final duracion =
                                HistorialExcelService.formatearDuracion(
                                    l['duracion_segundos'] ?? 0);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _colorEstado(estado)
                                      .withValues(alpha: 0.25),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: _colorEstado(estado)
                                          .withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      tipo.toLowerCase().contains('saliente')
                                          ? Icons.call_made_rounded
                                          : Icons.call_received_rounded,
                                      color: _colorEstado(estado),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tipo,
                                          style: TextStyle(
                                            color: _colorEstado(estado),
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Emisor: ${participantes.emisor}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Text(
                                          'Receptor: ${participantes.receptor}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          fecha,
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          'Estado: $estado · Duración: $duracion',
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
