// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

window.dataLayer = window.dataLayer || [];
window.dataLayer.push({
  'gtm.start': new Date().getTime(),
  event: 'gtm.js'
});


// Setup listening to send Google Analytics events when any element
// with a 'data-ga-click-event' attribute is clicked.
window.addEventListener('DOMContentLoaded', function () {
  function sendEvent(e) {
    // Create a custom event in Google Tag Manager, which we then have
    // configured GTM to forward to Google Analytics.
    window.dataLayer.push({
      event: 'custom-event',
      customEventCategory: 'click',
      customEventAction: e.currentTarget.dataset.gaClickEvent,
      customEventLabel: 'path:' + window.location.pathname,
      customEventValue: 1
    });
  }
  function addListeners() {
    var elements = document.querySelectorAll('[data-ga-click-event]');
    for (var i = 0; i < elements.length; i++) {
      elements[i].addEventListener('click', sendEvent);
    }
  }
  addListeners();
});
