import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "cliproxyQuota"

    StyledText {
        width: parent.width
        text: "CLIProxyAPI Quota Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "The API key is looked up at every fetch, first source that answers wins: the vault command, then pi's CLIProxyAPI config, then the literal key below. Nothing here is required on a machine where pi is already configured."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "vaultCommand"
        label: "Vault Lookup Command"
        description: "Shell command printing the API key, e.g. a secret-tool lookup against KeePassXC or GNOME Keyring. Clear the field to skip the vault entirely."
        defaultValue: "secret-tool lookup Title \"cliproxyapi api key\""
        placeholder: "secret-tool lookup Title \"cliproxyapi api key\""
    }

    StringSetting {
        settingKey: "endpointOverride"
        label: "Endpoint URL"
        description: "CLIProxyAPI server URL. Any path is stripped to the origin, so pasting an /v1 base works. Leave empty to use pi's configured endpoint."
        defaultValue: ""
        placeholder: "https://your-proxy.example.com"
    }

    StringSetting {
        settingKey: "literalKey"
        label: "API Key (literal)"
        description: "Last resort when neither the vault nor pi's config holds the key. Stored in plain text in the DMS plugin settings — prefer the vault command."
        defaultValue: ""
        placeholder: ""
    }

    SliderSetting {
        settingKey: "refreshInterval"
        label: "Refresh Interval"
        description: "How often quota is fetched. The server caches for two minutes, so polling faster only re-reads its cache."
        defaultValue: 2
        minimum: 1
        maximum: 30
        unit: "min"
        leftIcon: "schedule"
    }
}
