import Foundation

/// Hand-written wording for one rule. Placeholders: `{detail}`, `{agent}`, `{file}`, `{scope}`.
struct RuleWording: Sendable {
    let what: String
    let impact: String
    /// Short noun phrase for listing this rule next to another one, and for the model.
    let label: String
}

/// The built-in explanations, one per rule and language.
enum FallbackTemplates {
    static func wording(for rule: RuleID, language: ExplanationLanguage) -> RuleWording {
        language == .french ? french(rule) : english(rule)
    }

    static func recommendation(for action: RecommendedAction, severity: Severity, language: ExplanationLanguage) -> String {
        switch (action, severity, language) {
        case (.revert, .critical, .english): return "Warden recommends reverting it, unless you made this change yourself."
        case (.revert, .critical, .french): return "Warden recommande d'annuler, sauf si tu as fait ce changement toi-même."
        case (.revert, .info, .english): return "Warden recommends reverting it if you did not expect this."
        case (.revert, .info, .french): return "Warden recommande d'annuler si tu ne t'y attendais pas."
        case (.accept, _, .english): return "Warden recommends accepting it if you expected this change."
        case (.accept, _, .french): return "Warden recommande d'accepter si tu t'attendais à ce changement."
        }
    }

    static func alsoFound(_ labels: [String], language: ExplanationLanguage) -> String {
        let list = labels.joined(separator: ", ")
        return language == .french ? "Warden a aussi détecté : \(list)." : "Warden also found: \(list)."
    }

    // swiftlint:disable line_length cyclomatic_complexity
    private static func english(_ rule: RuleID) -> RuleWording {
        switch rule {
        case .hookChanged:
            return .init(what: "A hook ({detail}) was added or changed in {file}.", impact: "This command will run by itself during every {agent} session, {scope}.", label: "a new or changed hook")
        case .mcpServerAdded:
            return .init(what: "A new MCP server ({detail}) was added to {file}.", impact: "{agent} will connect to it and can send it data from your work {scope}.", label: "a new MCP server")
        case .mcpServerChanged:
            return .init(what: "The connection settings of the MCP server {detail} changed in {file}.", impact: "{agent} may now send your data and login tokens somewhere else {scope}.", label: "a changed MCP server")
        case .sensitiveEnvironment:
            return .init(what: "A sensitive network setting ({detail}) changed in {file}.", impact: "Traffic from {agent} could go through another server, which could read your prompts and keys {scope}.", label: "a sensitive network setting")
        case .credentialHelper:
            return .init(what: "The helper program that provides credentials ({detail}) changed in {file}.", impact: "{agent} will run this program to get your keys, so it can read or replace them {scope}.", label: "a credential helper")
        case .commandSetting:
            return .init(what: "A setting that launches a program ({detail}) changed in {file}.", impact: "{agent} will run this program by itself {scope}.", label: "a program launched by a setting")
        case .allProjectMcpServersEnabled:
            return .init(what: "Automatic approval of project MCP servers was turned on in {file}.", impact: "{agent} will connect to any MCP server a repository declares, without asking you, {scope}.", label: "automatic MCP approval")
        case .projectMcpServerApproved:
            return .init(what: "A project MCP server ({detail}) was approved in {file}.", impact: "{agent} will start this server without asking you {scope}.", label: "an approved MCP server")
        case .permissionWidened:
            return .init(what: "The permissions of {agent} were widened ({detail}) in {file}.", impact: "{agent} can now run commands or reach the network without asking you first {scope}.", label: "wider permissions")
        case .projectTrustGranted:
            return .init(what: "A project was marked as trusted ({detail}) in {file}.", impact: "{agent} will no longer show its safety prompt {scope}.", label: "a project marked as trusted")
        case .pluginAdded:
            return .init(what: "A new plugin or plugin source ({detail}) was added to {file}.", impact: "A plugin can add commands, hooks and instructions to {agent} {scope}.", label: "a new plugin")
        case .hiddenText:
            return .init(what: "Text you cannot see was added to {file}.", impact: "{agent} reads this hidden text as instructions, even though it does not appear on screen, {scope}.", label: "hidden text")
        case .bypassInstruction:
            return .init(what: "An instruction telling the agent to skip its safeguards was added to {file}.", impact: "{agent} could stop asking for your confirmation or hide what it does {scope}.", label: "an instruction to skip safeguards")
        case .remoteCodeExecution:
            return .init(what: "An instruction that downloads and runs code from the internet was added to {file}.", impact: "{agent} could run a program nobody has reviewed on your Mac {scope}.", label: "remote code execution")
        case .secretAccess:
            return .init(what: "An instruction that reads or sends secrets was added to {file}.", impact: "{agent} could expose your keys, passwords or data {scope}.", label: "access to secrets")
        case .encodedPayload:
            return .init(what: "A long encoded text that nobody can read was added to {file}.", impact: "{agent} can decode and follow it, while you cannot tell what it says, {scope}.", label: "an encoded payload")
        case .shellCommandMentioned:
            return .init(what: "New instructions in {file} mention a shell command ({detail}).", impact: "{agent} may run this command {scope}.", label: "a shell command")
        case .urlMentioned:
            return .init(what: "New instructions in {file} mention a web address ({detail}).", impact: "{agent} may visit this address {scope}.", label: "a web address")
        case .fileCreated:
            return .init(what: "The file {file} was created.", impact: "{agent} will now read this file {scope}.", label: "a new file")
        case .fileDeleted:
            return .init(what: "The file {file} was deleted.", impact: "{agent} loses the settings it contained {scope}.", label: "a deleted file")
        case .malformedConfig:
            return .init(what: "Warden can no longer read {file}: its format is broken or unusual.", impact: "{agent} may still read it, so it could hide a change Warden cannot see {scope}.", label: "an unreadable file")
        case .otherChange:
            return .init(what: "A setting changed in {file} ({detail}).", impact: "This changes how {agent} behaves {scope}, but it does not match a known risk.", label: "another setting")
        }
    }

    private static func french(_ rule: RuleID) -> RuleWording {
        switch rule {
        case .hookChanged:
            return .init(what: "Un hook ({detail}) a été ajouté ou modifié dans {file}.", impact: "Cette commande se lancera toute seule pendant chaque session {agent}, {scope}.", label: "un hook ajouté ou modifié")
        case .mcpServerAdded:
            return .init(what: "Un nouveau serveur MCP ({detail}) a été ajouté à {file}.", impact: "{agent} s'y connectera et pourra lui envoyer des données de ton travail {scope}.", label: "un nouveau serveur MCP")
        case .mcpServerChanged:
            return .init(what: "Les réglages de connexion du serveur MCP {detail} ont changé dans {file}.", impact: "{agent} peut désormais envoyer tes données et tes jetons de connexion ailleurs {scope}.", label: "un serveur MCP modifié")
        case .sensitiveEnvironment:
            return .init(what: "Un réglage réseau sensible ({detail}) a changé dans {file}.", impact: "Le trafic de {agent} pourrait passer par un autre serveur, capable de lire tes messages et tes clés, {scope}.", label: "un réglage réseau sensible")
        case .credentialHelper:
            return .init(what: "Le programme qui fournit tes identifiants ({detail}) a changé dans {file}.", impact: "{agent} lancera ce programme pour obtenir tes clés, il pourra donc les lire ou les remplacer {scope}.", label: "un programme d'identifiants")
        case .commandSetting:
            return .init(what: "Un réglage qui lance un programme ({detail}) a changé dans {file}.", impact: "{agent} lancera ce programme tout seul {scope}.", label: "un programme lancé par un réglage")
        case .allProjectMcpServersEnabled:
            return .init(what: "L'approbation automatique des serveurs MCP de projet a été activée dans {file}.", impact: "{agent} se connectera à tout serveur MCP déclaré par un dépôt, sans te demander, {scope}.", label: "l'approbation automatique MCP")
        case .projectMcpServerApproved:
            return .init(what: "Un serveur MCP de projet ({detail}) a été approuvé dans {file}.", impact: "{agent} lancera ce serveur sans te demander {scope}.", label: "un serveur MCP approuvé")
        case .permissionWidened:
            return .init(what: "Les permissions de {agent} ont été élargies ({detail}) dans {file}.", impact: "{agent} peut désormais lancer des commandes ou accéder au réseau sans te demander {scope}.", label: "des permissions élargies")
        case .projectTrustGranted:
            return .init(what: "Un projet a été marqué comme fiable ({detail}) dans {file}.", impact: "{agent} n'affichera plus son avertissement de sécurité {scope}.", label: "un projet marqué comme fiable")
        case .pluginAdded:
            return .init(what: "Un nouveau plugin ou une nouvelle source de plugins ({detail}) a été ajouté à {file}.", impact: "Un plugin peut ajouter des commandes, des hooks et des instructions à {agent} {scope}.", label: "un nouveau plugin")
        case .hiddenText:
            return .init(what: "Du texte invisible a été ajouté à {file}.", impact: "{agent} lit ce texte caché comme des instructions, même s'il n'apparaît pas à l'écran, {scope}.", label: "du texte invisible")
        case .bypassInstruction:
            return .init(what: "Une consigne demandant à l'agent de contourner ses protections a été ajoutée à {file}.", impact: "{agent} pourrait cesser de te demander confirmation ou cacher ce qu'il fait {scope}.", label: "une consigne de contournement")
        case .remoteCodeExecution:
            return .init(what: "Une consigne qui télécharge et exécute du code depuis internet a été ajoutée à {file}.", impact: "{agent} pourrait lancer sur ton Mac un programme que personne n'a vérifié {scope}.", label: "l'exécution de code distant")
        case .secretAccess:
            return .init(what: "Une consigne qui lit ou envoie des secrets a été ajoutée à {file}.", impact: "{agent} pourrait exposer tes clés, tes mots de passe ou tes données {scope}.", label: "un accès à des secrets")
        case .encodedPayload:
            return .init(what: "Un long texte encodé, illisible pour un humain, a été ajouté à {file}.", impact: "{agent} peut le décoder et le suivre, alors que toi tu ne peux pas savoir ce qu'il dit, {scope}.", label: "un contenu encodé")
        case .shellCommandMentioned:
            return .init(what: "De nouvelles instructions dans {file} mentionnent une commande shell ({detail}).", impact: "{agent} pourrait lancer cette commande {scope}.", label: "une commande shell")
        case .urlMentioned:
            return .init(what: "De nouvelles instructions dans {file} mentionnent une adresse web ({detail}).", impact: "{agent} pourrait consulter cette adresse {scope}.", label: "une adresse web")
        case .fileCreated:
            return .init(what: "Le fichier {file} a été créé.", impact: "{agent} va désormais lire ce fichier {scope}.", label: "un nouveau fichier")
        case .fileDeleted:
            return .init(what: "Le fichier {file} a été supprimé.", impact: "{agent} perd les réglages qu'il contenait {scope}.", label: "un fichier supprimé")
        case .malformedConfig:
            return .init(what: "Warden ne peut plus lire {file} : son format est cassé ou inhabituel.", impact: "{agent} peut quand même le lire, il pourrait donc cacher un changement que Warden ne voit pas {scope}.", label: "un fichier illisible")
        case .otherChange:
            return .init(what: "Un réglage a changé dans {file} ({detail}).", impact: "Cela modifie le comportement de {agent} {scope}, mais ne correspond à aucun risque connu.", label: "un autre réglage")
        }
    }
    // swiftlint:enable line_length cyclomatic_complexity
}
