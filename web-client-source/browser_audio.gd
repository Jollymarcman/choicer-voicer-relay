extends RefCounted

const DubPack = preload("res://dub_pack.gd")

# Godot's Web audio effects can draw a live spectrum yet return no recording.
# Capture the same microphone as PCM in the browser and hand a WAV to Godot.
const BRIDGE_SOURCE := """
(() => {
  if (window.CVAudioBridge) return;
  const bridge = {
    state: 'idle', error: '', context: null, stream: null, source: null,
    processor: null, gainNode: null, selectedDeviceId: '', inputGain: 1,
    inputDevicesJson: '[]',
    inputLevel: 0,
    chunks: [], capturing: false, wavBase64: '', waveformJson: '', generation: 0,
    prepare() {
      if (this.state === 'ready' || this.state === 'pending') return;
      this.configureDevice(this.selectedDeviceId);
    },
    async configureDevice(deviceId) {
      if (this.capturing) return;
      this.error = '';
      this.state = 'pending';
      this.selectedDeviceId = deviceId || '';
      const Context = window.AudioContext || window.webkitAudioContext;
      if (!Context || !navigator.mediaDevices?.getUserMedia) {
        this.state = 'error'; this.error = 'Browser microphone API is unavailable'; return;
      }
      try {
        if (!this.context) this.context = new Context();
        await this.context.resume();
        if (this.source) this.source.disconnect();
        if (this.processor) this.processor.disconnect();
        if (this.gainNode) this.gainNode.disconnect();
        if (this.stream) this.stream.getTracks().forEach(track => track.stop());
        const audio = deviceId ? {deviceId: {exact: deviceId}} : true;
        this.stream = await navigator.mediaDevices.getUserMedia({audio});
        this.source = this.context.createMediaStreamSource(this.stream);
        this.gainNode = this.context.createGain();
        this.gainNode.gain.value = this.inputGain;
        this.processor = this.context.createScriptProcessor(4096, 1, 1);
        const silent = this.context.createGain();
        silent.gain.value = 0;
        this.processor.onaudioprocess = event => {
          const data = event.inputBuffer.getChannelData(0);
          let squares = 0;
          for (let i = 0; i < data.length; i++) squares += data[i] * data[i];
          this.inputLevel = Math.sqrt(squares / Math.max(1, data.length));
          if (this.capturing) this.chunks.push(new Float32Array(data));
        };
        this.source.connect(this.gainNode);
        this.gainNode.connect(this.processor);
        this.processor.connect(silent);
        silent.connect(this.context.destination);
        await this.refreshDeviceList();
        this.state = 'ready';
      } catch (error) {
        this.state = 'error'; this.error = String(error);
      }
    },
    async refreshDeviceList() {
      const devices = await navigator.mediaDevices.enumerateDevices();
      this.inputDevicesJson = JSON.stringify(devices
        .filter(device => device.kind === 'audioinput')
        .map((device, index) => ({id: device.deviceId, label: device.label || `Microphone ${index + 1}`})));
    },
    async refreshDevices() {
      if (this.state !== 'ready') { this.prepare(); return; }
      this.state = 'pending';
      try { await this.refreshDeviceList(); }
      catch (error) { this.error = String(error); }
      this.state = 'ready';
    },
    listInputDevicesJson() { return this.inputDevicesJson; },
    setInputGain(value) {
      this.inputGain = Math.max(0, Math.min(2, Number(value) || 0));
      if (this.gainNode) this.gainNode.gain.setTargetAtTime(this.inputGain, this.context.currentTime, 0.02);
    },
    getInputLevel() { return this.inputLevel; },
    getState() { return this.state; },
    getError() { return this.error; },
    getSelectedDeviceId() { return this.selectedDeviceId; },
    start() {
      if (this.state !== 'ready') return false;
      this.chunks = [];
      this.wavBase64 = '';
      this.capturing = true;
      return true;
    },
    stop() {
      if (!this.capturing) return false;
      this.capturing = false;
      let count = 0;
      for (const chunk of this.chunks) count += chunk.length;
      if (!count) return false;
      const wav = new Uint8Array(44 + count * 2);
      const view = new DataView(wav.buffer);
      const put = (at, text) => { for (let i = 0; i < text.length; i++) wav[at + i] = text.charCodeAt(i); };
      put(0, 'RIFF'); view.setUint32(4, wav.length - 8, true); put(8, 'WAVE');
      put(12, 'fmt '); view.setUint32(16, 16, true);
      view.setUint16(20, 1, true); view.setUint16(22, 1, true);
      view.setUint32(24, this.context.sampleRate, true);
      view.setUint32(28, this.context.sampleRate * 2, true);
      view.setUint16(32, 2, true); view.setUint16(34, 16, true);
      put(36, 'data'); view.setUint32(40, count * 2, true);
      let index = 44;
      for (const chunk of this.chunks) {
        for (const value of chunk) {
          const sample = Math.max(-1, Math.min(1, value));
          view.setInt16(index, sample < 0 ? Math.round(sample * 32768) : Math.round(sample * 32767), true);
          index += 2;
        }
      }
      this.chunks = [];
      let binary = '';
      for (let at = 0; at < wav.length; at += 16384) {
        binary += String.fromCharCode(...wav.subarray(at, at + 16384));
      }
      this.wavBase64 = btoa(binary);
      return true;
    },
    takeWavBase64() {
      const result = this.wavBase64;
      this.wavBase64 = '';
      return result;
    },
    analyzeAudio(base64) {
      if (!this.context || !base64) return;
      const generation = ++this.generation;
      this.waveformJson = '';
      const binary = atob(base64);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
      this.context.decodeAudioData(bytes.buffer).then(buffer => {
        if (generation !== this.generation) return;
        const channels = [];
        for (let c = 0; c < buffer.numberOfChannels; c++) channels.push(buffer.getChannelData(c));
        const averages = [], maxima = [];
        const frameCount = Math.ceil(buffer.duration * 60);
        for (let frame = 0; frame < frameCount; frame++) {
          const start = Math.floor(frame * buffer.sampleRate / 60);
          const end = Math.min(buffer.length, Math.floor((frame + 1) * buffer.sampleRate / 60));
          let peak = 0, squares = 0, count = 0;
          for (let i = start; i < end; i++) {
            let value = 0;
            for (const channel of channels) value += channel[i] / channels.length;
            const abs = Math.abs(value);
            peak = Math.max(peak, abs); squares += value * value; count++;
          }
          const rms = Math.sqrt(squares / Math.max(1, count));
          // Godot's spectrum analyser reports much lower magnitudes than the
          // decoded PCM peak/RMS values below. Attenuate by 12 dB so the same
          // original waveform drawer has a similar height to the desktop UI.
          const level = amplitude => Math.round(Math.max(0, Math.min(1,
            (60 + 20 * Math.log10(Math.max(amplitude * 0.25, 0.000001))) / 60)) * 255);
          maxima.push(level(peak)); averages.push(level(rms));
        }
        this.waveformJson = JSON.stringify({average: averages, max: maxima, pitch: []});
      }).catch(() => { if (generation === this.generation) this.waveformJson = ''; });
    },
    takeWaveformJson() {
      const result = this.waveformJson;
      this.waveformJson = '';
      return result;
    },
    close() {
      this.capturing = false;
      if (this.stream) this.stream.getTracks().forEach(track => track.stop());
      if (this.context) this.context.close();
      this.stream = null; this.context = null; this.source = null;
      this.processor = null; this.gainNode = null; this.inputLevel = 0;
      this.state = 'idle';
    }
  };
  window.CVAudioBridge = bridge;
})();
"""


static func setup() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(BRIDGE_SOURCE, true)


static func interface() -> JavaScriptObject:
	if OS.has_feature("web"):
		return JavaScriptBridge.get_interface("CVAudioBridge")
	return null


static func take_recording() -> AudioStreamWAV:
	var bridge := interface()
	if not bridge:
		return null
	var encoded := str(bridge.takeWavBase64())
	if encoded.is_empty():
		return null
	return DubPack._wav_from_file_bytes(Marshalls.base64_to_raw(encoded))


static func take_waveform() -> Dictionary:
	var bridge := interface()
	if not bridge:
		return {}
	var source := str(bridge.takeWaveformJson())
	var parsed = JSON.parse_string(source) if not source.is_empty() else null
	if not parsed is Dictionary:
		return {}
	return {
		"average": PackedByteArray(parsed.get("average", [])),
		"max": PackedByteArray(parsed.get("max", [])),
		"pitch": PackedByteArray(parsed.get("pitch", [])),
	}


static func wait_for_waveform(timeout_seconds: float = 1.0) -> Dictionary:
	var bridge := interface()
	if not bridge:
		return {}
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		var waveform := take_waveform()
		if not waveform.is_empty():
			return waveform
		await Engine.get_main_loop().create_timer(0.05).timeout
		elapsed += 0.05
	return take_waveform()
