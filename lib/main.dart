import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

/// Modelo fine-tuneado que viene dentro de la app (sale de Colab).
const String rutaModeloPropio = 'assets/models/juguetes.tflite';

/// Confianza mínima inicial. Con 0.75 desaparecen los falsos positivos
/// de la v1 (autos amarillos detectados al 61-70 %).
const double confianzaInicial = 0.75;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const DetectorApp());
}

class DetectorApp extends StatelessWidget {
  const DetectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Detector de Juguetes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.green, brightness: Brightness.dark),
      home: const PantallaDetector(),
    );
  }
}

class PantallaDetector extends StatefulWidget {
  const PantallaDetector({super.key});

  @override
  State<PantallaDetector> createState() => _PantallaDetectorState();
}

class _PantallaDetectorState extends State<PantallaDetector> {
  final _controlador = YOLOViewController();

  String? _rutaModelo;
  String _nombreModelo = '';
  bool _esModeloPropio = false;
  List<YOLOResult> _detecciones = [];
  double _fps = 0;
  double _confianza = confianzaInicial;
  bool _linterna = false;
  bool _panelAbierto = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _elegirModeloInicial();
  }

  Future<void> _elegirModeloInicial() async {
    try {
      await rootBundle.load(rutaModeloPropio);
      setState(() {
        _rutaModelo = rutaModeloPropio;
        _nombreModelo = 'juguetes v1 (fine-tuned)';
        _esModeloPropio = true;
      });
    } catch (_) {
      setState(() {
        _rutaModelo = YOLO.defaultOfficialModel() ?? 'yolo26n';
        _nombreModelo = 'prueba COCO';
        _esModeloPropio = false;
      });
    }
  }

  /// Permite cargar un .tflite nuevo (por ejemplo la v2 entrenada en Colab
  /// desde la tablet) sin compilar otra APK.
  Future<void> _cargarModeloDesdeArchivo() async {
    final archivo = await FilePicker.pickFile(dialogTitle: 'Elige un modelo .tflite');
    final ruta = archivo?.path;
    if (ruta == null) return;
    if (!ruta.toLowerCase().endsWith('.tflite')) {
      _aviso('Ese archivo no es un modelo .tflite');
      return;
    }
    try {
      await _controlador.switchModel(ruta, YOLOTask.detect);
      await _controlador.setConfidenceThreshold(_confianza);
      setState(() {
        _nombreModelo = archivo!.name;
        _esModeloPropio = true;
        _error = null;
        _detecciones = [];
      });
      _aviso('Modelo cargado: ${archivo!.name}');
    } catch (e) {
      _aviso('No se pudo cargar el modelo: $e');
    }
  }

  Future<void> _volverAlModeloIncluido() async {
    await _controlador.switchModel(rutaModeloPropio, YOLOTask.detect);
    await _controlador.setConfidenceThreshold(_confianza);
    setState(() {
      _nombreModelo = 'juguetes v1 (fine-tuned)';
      _esModeloPropio = true;
      _detecciones = [];
    });
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  @override
  Widget build(BuildContext context) {
    final ruta = _rutaModelo;
    return Scaffold(
      backgroundColor: Colors.black,
      body: ruta == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Positioned.fill(
                  child: YOLOView(
                    controller: _controlador,
                    modelPath: ruta,
                    task: YOLOTask.detect,
                    confidenceThreshold: _confianza,
                    onResult: (r) {
                      if (mounted) setState(() => _detecciones = r);
                    },
                    onPerformanceMetrics: (m) {
                      if (mounted) setState(() => _fps = m.fps);
                    },
                    onModelError: (e, rutaFallida, tarea) {
                      if (mounted) setState(() => _error = '$e');
                    },
                  ),
                ),
                _barraSuperior(),
                _panelInferior(),
                if (_error != null) _mensajeError(_error!),
              ],
            ),
    );
  }

  Widget _barraSuperior() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _etiqueta('Modelo: $_nombreModelo', _esModeloPropio ? Colors.green : Colors.orange),
            const Spacer(),
            _etiqueta('${_fps.toStringAsFixed(1)} FPS', Colors.blueGrey),
          ],
        ),
      ),
    );
  }

  Widget _panelInferior() {
    final luchadores = _detecciones.where((d) => d.className == 'luchador').length;
    final rescatistas = _detecciones.where((d) => d.className == 'rescatista').length;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Detecciones actuales
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: _detecciones.isEmpty
                    ? [_etiqueta('Apunta la cámara a un juguete', Colors.black54)]
                    : _detecciones
                        .map((d) => _etiqueta(
                              '${d.className}  ${(d.confidence * 100).toStringAsFixed(0)} %',
                              d.className == 'luchador' ? Colors.indigo : Colors.teal.shade700,
                            ))
                        .toList(),
              ),
              const SizedBox(height: 8),
              // Panel de control
              Container(
                constraints: const BoxConstraints(maxWidth: 720),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text('🤼 $luchadores   🦺 $rescatistas',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Linterna',
                          icon: Icon(_linterna ? Icons.flashlight_on : Icons.flashlight_off),
                          onPressed: () async {
                            await _controlador.setTorchMode(!_linterna);
                            setState(() => _linterna = !_linterna);
                          },
                        ),
                        IconButton(
                          tooltip: 'Cambiar cámara',
                          icon: const Icon(Icons.cameraswitch),
                          onPressed: () => _controlador.switchCamera(),
                        ),
                        IconButton(
                          tooltip: _panelAbierto ? 'Ocultar controles' : 'Mostrar controles',
                          icon: Icon(_panelAbierto ? Icons.expand_more : Icons.tune),
                          onPressed: () => setState(() => _panelAbierto = !_panelAbierto),
                        ),
                      ],
                    ),
                    if (_panelAbierto) ...[
                      Row(
                        children: [
                          const Text('Confianza mínima', style: TextStyle(fontSize: 16)),
                          Expanded(
                            child: Slider(
                              value: _confianza,
                              min: 0.25,
                              max: 0.95,
                              divisions: 14,
                              label: '${(_confianza * 100).round()} %',
                              onChanged: (v) {
                                setState(() => _confianza = v);
                                _controlador.setConfidenceThreshold(v);
                              },
                            ),
                          ),
                          SizedBox(
                            width: 56,
                            child: Text('${(_confianza * 100).round()} %',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.folder_open),
                            label: const Text('Cargar modelo .tflite'),
                            onPressed: _cargarModeloDesdeArchivo,
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.restore),
                            label: const Text('Modelo incluido (v1)'),
                            onPressed: _volverAlModeloIncluido,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mensajeError(String texto) {
    return Center(
      child: GestureDetector(
        onTap: () => setState(() => _error = null),
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(16),
          color: Colors.red.shade900,
          child: Text('Error con el modelo (toca para cerrar):\n$texto', textAlign: TextAlign.center),
        ),
      ),
    );
  }

  Widget _etiqueta(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(20)),
      child: Text(texto, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
    );
  }
}
