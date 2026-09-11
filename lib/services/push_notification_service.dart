import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
// Importa tu archivo de configuración donde tienes la URL base de tu API
// import 'package:interfonia_gladiator/config.dart'; 

class PushNotificationService {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  // Llama a esta función justo después de que el usuario inicie sesión con éxito
  static Future<void> initAndRegisterToken(String rutUsuario) async {
    // 1. Solicitar permisos (esto hace que aparezca la alerta en iOS)
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('✅ Permisos de notificación concedidos.');

      // 2. Obtener el token actual de FCM
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        print('📱 Token FCM Obtenido: $token');
        await enviarTokenAlBackend(rutUsuario, token);
      }

      // 3. Escuchar si el token se actualiza (Firebase lo rota a veces)
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        print('🔄 Token FCM Actualizado: $newToken');
        enviarTokenAlBackend(rutUsuario, newToken);
      });

    } else {
      print('❌ Permisos de notificación denegados por el usuario.');
    }
  }

  static Future<void> enviarTokenAlBackend(String rut, String token) async {
    try {
      // Reemplaza esto con la URL real de tu backend (o usa tu config.dart)
      // final url = Uri.parse('${Config.apiUrl}/registrar-token');
      final url = Uri.parse('https://tu-dominio-o-ngrok.com/registrar-token'); 
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'rut': rut, 
          'token': token
        }),
      );

      if (response.statusCode == 200) {
        print('🌐 Token registrado exitosamente en el backend para el RUT $rut.');
      } else {
        print('⚠️ Error al registrar token en backend: ${response.body}');
      }
    } catch (e) {
      print('💥 Error en la petición POST /registrar-token: $e');
    }
  }
}