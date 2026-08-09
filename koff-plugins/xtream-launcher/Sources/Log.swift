import Foundation

/// Log sanitizé (compteurs/codes d'erreur uniquement) + flush immédiat
/// pour rester visible quand stdout est redirigé vers un fichier.
func xlog(_ message: String) {
    print(message)
    fflush(nil)
}
