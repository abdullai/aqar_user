/* eslint-disable no-undef */
// Firebase Cloud Messaging — service worker for Flutter Web (must be served as JavaScript, not SPA index.html).
// Config matches lib/firebase_options.dart → DefaultFirebaseOptions.web
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyB5Jumx3edRucy9Yj53A5GH50OJigb2oX4',
  authDomain: 'aqaruser-73df0.firebaseapp.com',
  projectId: 'aqaruser-73df0',
  storageBucket: 'aqaruser-73df0.firebasestorage.app',
  messagingSenderId: '396763698740',
  appId: '1:396763698740:web:0394828ec9dfa6d8b61c61',
  measurementId: 'G-CX3TTB2CDX',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] background message', payload);
  const title =
    payload.notification?.title ||
    payload.data?.title_ar ||
    payload.data?.title_en ||
    payload.data?.title ||
    'Aqar';
  const body =
    payload.notification?.body ||
    payload.data?.body_ar ||
    payload.data?.body_en ||
    payload.data?.body ||
    '';
  if (!title && !body) return;
  return self.registration.showNotification(title || 'Aqar', {
    body: body || '',
    data: payload.data || {},
  });
});
