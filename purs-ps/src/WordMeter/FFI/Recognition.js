export const recognitionApiAvailable = () => {
  return !!(window.SpeechRecognition || window.webkitSpeechRecognition);
};

export const createRecognition = () => {
  const SpeechRecognitionConstructor =
    window.SpeechRecognition || window.webkitSpeechRecognition;
  
  if (!SpeechRecognitionConstructor) {
    return { tag: 'Left', value: 'RecognitionConstructError' };
  }

  try {
    const instance = new SpeechRecognitionConstructor();
    instance.continuous = true;
    instance.interimResults = true;
    return { tag: 'Right', value: instance };
  } catch (error) {
    return { tag: 'Left', value: 'RecognitionConstructError' };
  }
};

export const setRecognitionLocale = (instance) => (locale) => () => {
  instance.lang = locale;
};

export const attachResultListener = (instance) => (callback) => () => {
  instance.onresult = (event) => {
    for (let i = event.resultIndex; i < event.results.length; i++) {
      if (event.results[i].isFinal) {
        const transcript = event.results[i][0].transcript;
        callback(transcript)(Date.now())();
      }
    }
  };
};

export const attachErrorListener = (instance) => (callback) => () => {
  instance.onerror = (event) => {
    callback(event.error)(event.message || '')();
  };
};

export const attachEndListener = (instance) => (callback) => () => {
  instance.onend = () => {
    callback();
  };
};

export const startRecognition = (instance) => () => {
  try {
    instance.start();
    return { tag: 'Right', value: {} };
  } catch (error) {
    if (error.name === 'InvalidStateError') {
      return { tag: 'Left', value: 'RecognitionStartUnavailable' };
    }
    return {
      tag: 'Left',
      value: { tag: 'RecognitionStartException', value: error.message || '' }
    };
  }
};

export const stopRecognition = (instance) => () => {
  try {
    instance.stop();
    return { tag: 'Right', value: {} };
  } catch (error) {
    return {
      tag: 'Left',
      value: { tag: 'RecognitionStopException', value: error.message || '' }
    };
  }
};
