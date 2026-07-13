import AppKit
import Vision

/// 스크린샷에서 텍스트를 추출한다(온디바이스 · 무료 · 오프라인).
/// 결과 콜백은 항상 메인 스레드에서 호출된다.
enum OCRService {
    static func recognizeText(in image: NSImage, completion: @escaping (String?) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            let result: String?
            if error == nil,
               let observations = request.results as? [VNRecognizedTextObservation] {
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n")
                result = text.isEmpty ? nil : text
            } else {
                result = nil
            }
            DispatchQueue.main.async { completion(result) }
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ko-KR", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
}
