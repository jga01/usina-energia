# File: scripts/TextDB.gd
# Autoload this script as "TextDB"
extends Node

# Character Selection Screen
const CS_PLAYER_TURN: String = "Jogador %d, Escolha o Seu Personagem"
const CS_CHARACTER_NAME_LABEL_PLACEHOLDER: String = "Nome do Personagem"
const CS_CHARACTER_DESCRIPTION_LABEL_PLACEHOLDER: String = "Descricao do personagem..."
const CS_CONFIRM_NEXT_PLAYER_BUTTON: String = "Confirmar"
const CS_CONFIRM_START_GAME_BUTTON: String = "Jogar"
const CS_ALL_CONFIRMED_BUTTON: String = "Todos Confirmados"
const CS_NO_CHARACTERS_AVAILABLE: String = "Nenhum Personagem Disponivel!"
const CS_ERROR_NOT_ENOUGH_CHARS: String = "Erro: Personagens unicos insuficientes."
const CS_ERROR_CHARACTER_TAKEN: String = "Erro: %s pode ja estar escolhido."

# Display Screen (Main Game UI)
# const DISPLAY_POWER_GRID_STATUS_TITLE: String = "Status da Rede Eletrica" # Removed/Replaced
# const DISPLAY_ENERGY_LEVEL_PERCENT: String = "%d%%" # Removed, core shows this visually
const DISPLAY_STATUS_WAITING: String = "Aguardando Inicio..."
const DISPLAY_STATUS_STABLE: String = "Sistemas Estaveis"
const DISPLAY_STATUS_DANGER_SHUTDOWN_IMMINENT: String = "ALERTA: Desligamento Critico Iminente!"
const DISPLAY_STATUS_DANGER_MELTDOWN_IMMINENT: String = "PERIGO: Colapso da Rede Iminente!"
const DISPLAY_STATUS_WARNING_LOW_POWER: String = "Aviso: Energia Baixa"
const DISPLAY_STATUS_WARNING_HIGH_POWER: String = "Aviso: Energia Alta"

const DISPLAY_STABILITY_GOAL_SIMPLE: String = "Estabilidade: %ds / %ds" # Simplified for icon display
const DISPLAY_STABILITY_GOAL_SUCCESS_SIMPLE: String = "Estabilidade: SUCESSO!"
const DISPLAY_STABILITY_GOAL_WAITING_SIMPLE: String = "Estabilidade: --s / --s"
const DISPLAY_STABILITY_GOAL_FINAL_STATUS_PREFIX: String = "Resultado: "
const DISPLAY_GAME_RESETTING: String = "Reiniciando..."

const DISPLAY_DANGER_SHUTDOWN_COUNTDOWN: String = "DESLIGAMENTO EM: %.1fs"
const DISPLAY_DANGER_MELTDOWN_COUNTDOWN: String = "COLAPSO EM: %.1fs"

const DISPLAY_INDIVIDUAL_WIN_TEXT: String = "Vitoria Individual: Jogador %d"
const DISPLAY_GRID_SHUTDOWN_TEXT: String = "Desligamento da Rede"
const DISPLAY_GRID_MELTDOWN_TEXT: String = "Colapso da Rede"
const DISPLAY_ALL_ELIMINATED_TEXT: String = "Todos Eliminados"
const DISPLAY_LAST_PLAYER_STANDING_TEXT: String = "Ultimo Sobrevivente: Jogador %d"

const DISPLAY_INACTIVITY_WARNING: String = "ALERTA DE INATIVIDADE!\nDrenagem de energia acelerada!"

# Player Indicator
const PI_STASH_LABEL: String = "REDIRECIONADO:"
const PI_INTERACT_BUTTON: String = "INTERAGIR"
const PI_STATUS_LABEL_PREFIX: String = "Status: "
const PI_ELIMINATED_TEXT_SUFFIX: String = " (ELIMINADO)"
const PI_STATUS_ELIMINATED_GENERIC: String = "Eliminado."
const PI_BUTTON_ELIMINATED_TEXT: String = "---"
const PI_STASH_TARGET_UNKNOWN: String = "??"

# Player Action Feedback Statuses (used by GameManager, displayed by PlayerIndicator)
const STATUS_ELECTROCUTED: String = "ELETROCUTADO!"
const STATUS_STOLE_AMOUNT: String = "Redirecionou %.1f"
const STATUS_LOW_GRID_FOR_STEAL: String = "Rede Baixa Demais!"
const STATUS_UNKNOWN_CMD: String = "Comando Desconhecido"

# Events (Main Status Text during event)
const EVENT_SURGE_STATUS: String = "PICO DE DEMANDA ATIVO!"
const EVENT_EFFICIENCY_STATUS: String = "EFICIENCIA MAXIMA ATIVA!"
const EVENT_UNSTABLE_GRID_STATUS: String = "REDE INSTAVEL ATIVA!"

# Events (Large Overlay Titles)
const EVENT_UNKNOWN_TITLE: String = "EVENTO DESCONHECIDO" # Fallback for overlay
const EVENT_SURGE_TITLE_OVERLAY: String = "PICO DE DEMANDA!" # Shortened for overlay
const EVENT_EFFICIENCY_TITLE_OVERLAY: String = "EFICIENCIA MAXIMA!" # Shortened for overlay
const EVENT_UNSTABLE_GRID_TITLE_OVERLAY: String = "REDE INSTAVEL!" # Shortened for overlay
# Old alerts with "restam %ds" are effectively replaced by the new overlay + core visuals
# const EVENT_SURGE_ALERT: String = "AVISO: Pico de Demanda! (restam %ds)"
# const EVENT_EFFICIENCY_ALERT: String = "AVISO: Campanha de Eficiencia! (restam %ds)"
# const EVENT_UNSTABLE_GRID_ALERT: String = "ALERTA: REDE INSTAVEL! Risco de choque! (restam %ds)"


# Game Over Screen
const GO_TITLE_GAME_OVER_DEFAULT: String = "FIM DE JOGO"
const GO_OUTCOME_MESSAGE_DEFAULT_PREFIX: String = "Resultado: "
const GO_OUTCOME_UNKNOWN_NO_DATA: String = "Desconhecido (Nenhum dado recebido)"
const GO_PLAY_AGAIN_BUTTON: String = "Jogar Novamente"
const GO_MAIN_MENU_BUTTON: String = "Menu Principal"

const GO_TITLE_COOP_WIN: String = "VITORIA COOPERATIVA!"
const GO_MSG_COOP_WIN: String = "VITORIA!\n\nA rede eletrica esta estavel gracas ao seu esforco!"
const GO_TITLE_SHUTDOWN: String = "DESLIGAMENTO DA REDE"
const GO_MSG_SHUTDOWN: String = "DERROTA!\n\nA rede sofreu um desligamento critico."
const GO_TITLE_MELTDOWN: String = "COLAPSO DA REDE"
const GO_MSG_MELTDOWN: String = "DERROTA!\n\nA rede sofreu um colapso catastrófico!"
const GO_TITLE_INDIVIDUAL_WIN_PLAYER: String = "%s VENCE!"
const GO_TITLE_INDIVIDUAL_WIN_UNKNOWN: String = "VITORIA INDIVIDUAL"
const GO_MSG_INDIVIDUAL_WIN_PLAYER: String = "VITORIA INDIVIDUAL!\n\n%s acumulou poder suficiente!"
const GO_MSG_INDIVIDUAL_WIN_UNKNOWN: String = "Vitoria individual por um jogador."
const GO_TITLE_ALL_ELIMINATED: String = "TODOS ELIMINADOS"
const GO_MSG_ALL_ELIMINATED: String = "FALHA TOTAL!\n\nTodos os operadores foram eliminados."
const GO_TITLE_LAST_PLAYER_STANDING: String = "%s SOBREVIVE!"
const GO_TITLE_LAST_PLAYER_STANDING_UNKNOWN: String = "ULTIMO SOBREVIVENTE"
const GO_MSG_LAST_PLAYER_STANDING: String = "SOBREVIVENTE!\n\n%s e o ultimo operador de pe!"
const GO_MSG_LAST_PLAYER_STANDING_UNKNOWN: String = "Um operador sobreviveu."
const GO_MSG_CONCLUDED_REASON_PREFIX: String = "O jogo terminou. Motivo: %s"
const GO_LEADERBOARD_TITLE: String = "PLACAR FINAL"
const GO_LEADERBOARD_STASH_PREFIX: String = "Redirecionado: "
const GO_LEADERBOARD_GENERATED_PREFIX: String = "Gerado: "

# Main Menu
const MAIN_MENU_START_BUTTON_TEXT: String = "Iniciar"

# Generic / Shared
const GENERIC_PLAYER_LABEL_FORMAT: String = "Jogador %d"
