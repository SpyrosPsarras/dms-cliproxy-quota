.pragma library

var strings = {
    "%1 recorded": { fr: "%1 enregistrés", es: "%1 registrados" },
    "Mute taskbar warnings for %1": { fr: "Couper les alertes de la barre pour %1", es: "Silenciar avisos de la barra para %1" },
    "Unmute taskbar warnings for %1": { fr: "Rétablir les alertes de la barre pour %1", es: "Reactivar avisos de la barra para %1" },
    "no usage in 7 days": { fr: "aucune utilisation en 7 jours", es: "sin uso en 7 días" },
    "remaining": { fr: "restant", es: "restante" },
    "reset": { fr: "réinitialisé", es: "reiniciado" },
    "top of scale": { fr: "haut de l'échelle", es: "máximo de la escala" },
    "unattributed": { fr: "non attribué", es: "sin atribuir" },
    "unattributed: usage not reported per account": { fr: "non attribué : usage non rapporté par compte", es: "sin atribuir: uso no reportado por cuenta" },
    "Quota remaining": { fr: "Quota restant", es: "Cuota restante" },
    "Accounts": { fr: "Comptes", es: "Cuentas" },
    "Usage": { fr: "Utilisation", es: "Uso" },
    "All accounts": { fr: "Tous les comptes", es: "Todas las cuentas" },
    "Tokens per day": { fr: "Jetons par jour", es: "Tokens por día" },
    "Requests per day": { fr: "Requêtes par jour", es: "Solicitudes por día" },
    "Models": { fr: "Modèles", es: "Modelos" },
    "Today": { fr: "Aujourd'hui", es: "Hoy" },
    "7 days": { fr: "7 jours", es: "7 días" },
    "error": { fr: "erreur", es: "error" },
    "tokens": { fr: "jetons", es: "tokens" },
    "requests": { fr: "requêtes", es: "solicitudes" },
    "ok": { fr: "réussies", es: "correctas" },
    "failed": { fr: "échouées", es: "fallidas" },
    "over pace": { fr: "au-dessus du rythme", es: "sobre el ritmo" },
    "no data": { fr: "aucune donnée", es: "sin datos" },
    "no quota reported": { fr: "aucun quota signalé", es: "sin cuota reportada" },
    "no account is serving": { fr: "aucun compte en service", es: "ninguna cuenta en servicio" },
    "Loading…": { fr: "Chargement…", es: "Cargando…" },
    "Refreshing…": { fr: "Actualisation…", es: "Actualizando…" },
    "stale": { fr: "périmé", es: "desactualizado" },
    "Check the plugin settings or unlock your vault.": {
        fr: "Vérifiez les réglages du plugin ou déverrouillez votre coffre.",
        es: "Revisa los ajustes del plugin o desbloquea tu bóveda."
    },
    "The server sends a newer data format. Update this widget.": {
        fr: "Le serveur envoie un format de données plus récent. Mettez ce widget à jour.",
        es: "El servidor envía un formato de datos más reciente. Actualiza este widget."
    },
    "updated": { fr: "mis à jour", es: "actualizado" },
    "%1 ago": { fr: "il y a %1", es: "hace %1" },
    "Refresh": { fr: "Actualiser", es: "Actualizar" },
    "resets in": { fr: "réinitialisation dans", es: "se reinicia en" },
    "just now": { fr: "à l'instant", es: "ahora mismo" },
    "Other accounts": { fr: "Autres comptes", es: "Otras cuentas" },
    "disabled": { fr: "désactivé", es: "desactivado" },
    "unavailable": { fr: "indisponible", es: "no disponible" },
    "unsupported": { fr: "non pris en charge", es: "no compatible" },
    "last request": { fr: "dernière requête", es: "última solicitud" }
};

function tr(key, lang) {
    var entry = strings[key];
    if (!entry)
        return key;
    if (lang && entry[lang])
        return entry[lang];
    return key;
}
