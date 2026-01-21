#!/bin/bash

#===============================================================================
# DevOps Tools Installer - Ubuntu & Rocky Linux
# Autor: Script gerado por Euclides Pereira Novaes
# Versão: 1.0
# Descrição: Instala AWS CLI, Docker, Helm, Kubectl, Kustomize, Terraform, VSCode
#===============================================================================

set -o pipefail

# Cores para output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Configurações
readonly LOG_FILE="/var/log/devops-tools-installer.log"
readonly MAX_RETRIES=3
readonly RETRY_DELAY=5

# Variáveis globais
OS_TYPE=""
OS_VERSION=""
PKG_MANAGER=""
ARCH=""
HAS_GUI=false
DESKTOP_PATH=""

#===============================================================================
# FUNÇÕES DE UTILIDADE
#===============================================================================

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE" 2>/dev/null
}

print_header() {
    echo -e "\n${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} $1"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}\n"
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log "INFO" "$1"
}

print_success() {
    echo -e "${GREEN}[✓ OK]${NC} $1"
    log "SUCCESS" "$1"
}

print_warning() {
    echo -e "${YELLOW}[⚠ AVISO]${NC} $1"
    log "WARNING" "$1"
}

print_error() {
    echo -e "${RED}[✗ ERRO]${NC} $1"
    log "ERROR" "$1"
}

print_step() {
    echo -e "${CYAN}[PASSO]${NC} $1"
    log "STEP" "$1"
}

# Função para executar comandos com retry
execute_with_retry() {
    local cmd="$1"
    local description="$2"
    local attempt=1
    
    while [ $attempt -le $MAX_RETRIES ]; do
        print_status "Tentativa $attempt/$MAX_RETRIES: $description"
        
        if eval "$cmd" >> "$LOG_FILE" 2>&1; then
            return 0
        fi
        
        if [ $attempt -lt $MAX_RETRIES ]; then
            print_warning "Falha na tentativa $attempt. Aguardando ${RETRY_DELAY}s antes de retry..."
            sleep $RETRY_DELAY
        fi
        
        ((attempt++))
    done
    
    return 1
}

# Verificar se comando existe
command_exists() {
    command -v "$1" &> /dev/null
}

# Verificar se está rodando como root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Este script precisa ser executado como root (sudo)"
        exit 1
    fi
}

#===============================================================================
# DETECÇÃO DO SISTEMA OPERACIONAL
#===============================================================================

detect_os() {
    print_header "DETECTANDO SISTEMA OPERACIONAL"
    
    if [ ! -f /etc/os-release ]; then
        print_error "Arquivo /etc/os-release não encontrado. Sistema operacional não suportado."
        exit 1
    fi
    
    source /etc/os-release
    
    OS_VERSION="$VERSION_ID"
    
    # Detectar arquitetura
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *)
            print_error "Arquitetura $ARCH não suportada"
            exit 1
            ;;
    esac
    
    # Detectar tipo de OS baseado no ID e ID_LIKE
    case "$ID" in
        ubuntu|debian|linuxmint|pop)
            OS_TYPE="debian"
            PKG_MANAGER="apt"
            print_success "Sistema detectado: $PRETTY_NAME (Debian-based)"
            ;;
        rocky|rhel|centos|fedora|almalinux|oracle)
            OS_TYPE="rhel"
            if command_exists dnf; then
                PKG_MANAGER="dnf"
            else
                PKG_MANAGER="yum"
            fi
            print_success "Sistema detectado: $PRETTY_NAME (RHEL-based)"
            ;;
        *)
            # Verificar ID_LIKE para sistemas derivados
            if [[ "$ID_LIKE" == *"debian"* ]] || [[ "$ID_LIKE" == *"ubuntu"* ]]; then
                OS_TYPE="debian"
                PKG_MANAGER="apt"
                print_success "Sistema detectado: $PRETTY_NAME (Debian-based via ID_LIKE)"
            elif [[ "$ID_LIKE" == *"rhel"* ]] || [[ "$ID_LIKE" == *"fedora"* ]] || [[ "$ID_LIKE" == *"centos"* ]]; then
                OS_TYPE="rhel"
                if command_exists dnf; then
                    PKG_MANAGER="dnf"
                else
                    PKG_MANAGER="yum"
                fi
                print_success "Sistema detectado: $PRETTY_NAME (RHEL-based via ID_LIKE)"
            else
                print_error "Sistema operacional não suportado: $PRETTY_NAME"
                print_error "Este script suporta: Ubuntu, Debian, Rocky Linux, RHEL, CentOS, Fedora, AlmaLinux"
                exit 1
            fi
            ;;
    esac
    
    print_status "Arquitetura: $ARCH"
    print_status "Gerenciador de pacotes: $PKG_MANAGER"
    echo ""
}

#===============================================================================
# DETECÇÃO DE AMBIENTE GRÁFICO (GUI)
#===============================================================================

detect_gui() {
    print_step "Verificando ambiente gráfico..."
    
    # Métodos de detecção de GUI
    local gui_detected=false
    
    # Método 1: Verificar variável DISPLAY
    if [ -n "$DISPLAY" ]; then
        gui_detected=true
        print_status "GUI detectado via DISPLAY=$DISPLAY"
    fi
    
    # Método 2: Verificar se existe sessão gráfica ativa
    if [ -n "$XDG_CURRENT_DESKTOP" ]; then
        gui_detected=true
        print_status "Desktop Environment: $XDG_CURRENT_DESKTOP"
    fi
    
    # Método 3: Verificar se systemd tem target gráfico
    if systemctl get-default 2>/dev/null | grep -q "graphical"; then
        gui_detected=true
        print_status "Sistema configurado para modo gráfico (graphical.target)"
    fi
    
    # Método 4: Verificar se há display manager instalado
    local display_managers=("gdm" "gdm3" "lightdm" "sddm" "lxdm" "xdm")
    for dm in "${display_managers[@]}"; do
        if command_exists "$dm" || systemctl is-active --quiet "$dm" 2>/dev/null; then
            gui_detected=true
            print_status "Display Manager detectado: $dm"
            break
        fi
    done
    
    # Método 5: Verificar se há ambiente desktop instalado
    if [ "$OS_TYPE" = "debian" ]; then
        if dpkg -l | grep -qE "(gnome-shell|kde-plasma-desktop|xfce4|cinnamon|mate-desktop)" 2>/dev/null; then
            gui_detected=true
        fi
    elif [ "$OS_TYPE" = "rhel" ]; then
        if rpm -qa | grep -qE "(gnome-shell|plasma-desktop|xfce4|cinnamon|mate-desktop)" 2>/dev/null; then
            gui_detected=true
        fi
    fi
    
    if $gui_detected; then
        HAS_GUI=true
        print_success "Ambiente gráfico detectado"
        
        # Determinar caminho do Desktop
        local target_user=""
        local user_home=""
        
        # Tentar obter o utilizador real (não root)
        if [ -n "$SUDO_USER" ]; then
            target_user="$SUDO_USER"
        elif [ -n "$LOGNAME" ] && [ "$LOGNAME" != "root" ]; then
            target_user="$LOGNAME"
        elif [ -n "$USER" ] && [ "$USER" != "root" ]; then
            target_user="$USER"
        else
            # Procurar primeiro utilizador com UID >= 1000
            target_user=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}')
        fi
        
        if [ -n "$target_user" ]; then
            user_home=$(getent passwd "$target_user" | cut -d: -f6)
            
            # Exportar SUDO_USER para uso posterior se não estava definido
            export SUDO_USER="$target_user"
            
            # Verificar Desktop em português e inglês
            if [ -d "$user_home/Área de Trabalho" ]; then
                DESKTOP_PATH="$user_home/Área de Trabalho"
            elif [ -d "$user_home/Desktop" ]; then
                DESKTOP_PATH="$user_home/Desktop"
            elif [ -d "$user_home/Ambiente de Trabalho" ]; then
                DESKTOP_PATH="$user_home/Ambiente de Trabalho"
            else
                # Criar Desktop se não existir
                DESKTOP_PATH="$user_home/Desktop"
                mkdir -p "$DESKTOP_PATH"
                chown "$target_user:$target_user" "$DESKTOP_PATH"
            fi
            print_status "Utilizador detectado: $target_user"
            print_status "Desktop path: $DESKTOP_PATH"
        else
            print_warning "Não foi possível determinar o utilizador do sistema"
        fi
    else
        HAS_GUI=false
        print_status "Sistema sem ambiente gráfico (modo servidor)"
    fi
}

#===============================================================================
# PREPARAÇÃO DO SISTEMA
#===============================================================================

prepare_system() {
    print_header "PREPARANDO SISTEMA"
    
    print_step "Atualizando cache de pacotes..."
    
    if [ "$OS_TYPE" = "debian" ]; then
        if ! execute_with_retry "apt-get update" "Atualizar apt cache"; then
            print_error "Falha ao atualizar cache do apt"
            # Tentar corrigir problemas comuns
            print_status "Tentando corrigir problemas de repositório..."
            apt-get update --fix-missing >> "$LOG_FILE" 2>&1 || true
        fi
        
        print_step "Instalando dependências básicas..."
        execute_with_retry "apt-get install -y curl wget gnupg2 software-properties-common apt-transport-https ca-certificates lsb-release unzip" "Instalar dependências"
        
    elif [ "$OS_TYPE" = "rhel" ]; then
        if ! execute_with_retry "$PKG_MANAGER makecache" "Atualizar $PKG_MANAGER cache"; then
            print_warning "Falha ao atualizar cache, continuando..."
        fi
        
        print_step "Instalando dependências básicas..."
        execute_with_retry "$PKG_MANAGER install -y curl wget gnupg2 ca-certificates unzip yum-utils" "Instalar dependências"
        
        # Instalar EPEL se necessário (Rocky/RHEL/CentOS)
        if [[ "$ID" =~ ^(rocky|rhel|centos|almalinux)$ ]]; then
            print_step "Verificando/Instalando EPEL repository..."
            if ! rpm -q epel-release &>/dev/null; then
                execute_with_retry "$PKG_MANAGER install -y epel-release" "Instalar EPEL"
            else
                print_success "EPEL já instalado"
            fi
        fi
    fi
    
    print_success "Sistema preparado com sucesso"
}

#===============================================================================
# INSTALAÇÃO: AWS CLI
#===============================================================================

install_awscli() {
    print_header "INSTALANDO AWS CLI"
    
    # Verificar se já está instalado
    if command_exists aws; then
        local current_version=$(aws --version 2>&1 | cut -d' ' -f1 | cut -d'/' -f2)
        print_warning "AWS CLI já instalado (versão: $current_version)"
        read -p "Deseja reinstalar/atualizar? (s/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            print_status "Mantendo versão atual do AWS CLI"
            return 0
        fi
    fi
    
    print_step "Baixando AWS CLI v2..."
    
    local aws_arch="x86_64"
    [ "$ARCH" = "arm64" ] && aws_arch="aarch64"
    
    cd /tmp
    rm -rf aws awscliv2.zip
    
    if ! execute_with_retry "curl -fsSL 'https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip' -o awscliv2.zip" "Download AWS CLI"; then
        print_error "Falha ao baixar AWS CLI"
        return 1
    fi
    
    print_step "Extraindo e instalando..."
    unzip -q -o awscliv2.zip >> "$LOG_FILE" 2>&1
    
    if [ -f /usr/local/bin/aws ]; then
        ./aws/install --update >> "$LOG_FILE" 2>&1
    else
        ./aws/install >> "$LOG_FILE" 2>&1
    fi
    
    # Validação
    if command_exists aws; then
        local version=$(aws --version 2>&1)
        print_success "AWS CLI instalado: $version"
        rm -rf /tmp/aws /tmp/awscliv2.zip
        return 0
    else
        print_error "Falha na validação do AWS CLI"
        return 1
    fi
}

#===============================================================================
# INSTALAÇÃO: DOCKER
#===============================================================================

install_docker() {
    print_header "INSTALANDO DOCKER"
    
    # Verificar se já está instalado
    if command_exists docker; then
        local current_version=$(docker --version 2>&1 | cut -d' ' -f3 | tr -d ',')
        print_warning "Docker já instalado (versão: $current_version)"
        read -p "Deseja reinstalar? (s/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            print_status "Mantendo versão atual do Docker"
            return 0
        fi
    fi
    
    # Remover versões antigas
    print_step "Removendo versões antigas do Docker (se existirem)..."
    if [ "$OS_TYPE" = "debian" ]; then
        apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    else
        $PKG_MANAGER remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
    fi
    
    if [ "$OS_TYPE" = "debian" ]; then
        print_step "Configurando repositório Docker para Debian/Ubuntu..."
        
        # Determinar a distribuição base para o Docker
        # Linux Mint, Pop!_OS e outros derivados devem usar Ubuntu
        local docker_distro=""
        local docker_codename=""
        
        case "$ID" in
            ubuntu)
                docker_distro="ubuntu"
                docker_codename=$(lsb_release -cs 2>/dev/null)
                ;;
            debian)
                docker_distro="debian"
                docker_codename=$(lsb_release -cs 2>/dev/null)
                ;;
            linuxmint)
                docker_distro="ubuntu"
                # Linux Mint 22 = Ubuntu 24.04 (noble)
                # Linux Mint 21 = Ubuntu 22.04 (jammy)
                # Linux Mint 20 = Ubuntu 20.04 (focal)
                case "${VERSION_ID%%.*}" in
                    22) docker_codename="noble" ;;
                    21) docker_codename="jammy" ;;
                    20) docker_codename="focal" ;;
                    *) docker_codename="jammy" ;;  # fallback
                esac
                print_status "Linux Mint $VERSION_ID mapeado para Ubuntu $docker_codename"
                ;;
            pop)
                docker_distro="ubuntu"
                docker_codename=$(lsb_release -cs 2>/dev/null)
                # Pop!_OS usa mesmos codenames que Ubuntu geralmente
                ;;
            *)
                # Para outros derivados, tentar determinar base
                if [[ "$ID_LIKE" == *"ubuntu"* ]]; then
                    docker_distro="ubuntu"
                    docker_codename="jammy"  # fallback seguro
                elif [[ "$ID_LIKE" == *"debian"* ]]; then
                    docker_distro="debian"
                    docker_codename="bookworm"  # fallback seguro
                else
                    docker_distro="ubuntu"
                    docker_codename="jammy"
                fi
                ;;
        esac
        
        print_status "Usando repositório Docker: $docker_distro ($docker_codename)"
        
        # Adicionar chave GPG oficial do Docker
        install -m 0755 -d /etc/apt/keyrings
        rm -f /etc/apt/keyrings/docker.gpg  # Remover chave antiga se existir
        
        if ! curl -fsSL "https://download.docker.com/linux/${docker_distro}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null; then
            print_error "Falha ao baixar chave GPG do Docker"
            return 1
        fi
        chmod a+r /etc/apt/keyrings/docker.gpg
        
        # Adicionar repositório
        echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${docker_distro} ${docker_codename} stable" > /etc/apt/sources.list.d/docker.list
        
        apt-get update >> "$LOG_FILE" 2>&1
        
        print_step "Instalando Docker Engine..."
        if ! execute_with_retry "apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" "Instalar Docker"; then
            print_error "Falha ao instalar Docker"
            return 1
        fi
        
    elif [ "$OS_TYPE" = "rhel" ]; then
        print_step "Configurando repositório Docker para RHEL/Rocky..."
        
        # Adicionar repositório Docker
        $PKG_MANAGER config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >> "$LOG_FILE" 2>&1 || \
        curl -fsSL https://download.docker.com/linux/centos/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo
        
        print_step "Instalando Docker Engine..."
        if ! execute_with_retry "$PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" "Instalar Docker"; then
            print_error "Falha ao instalar Docker"
            return 1
        fi
    fi
    
    # Iniciar e habilitar serviço
    print_step "Iniciando serviço Docker..."
    systemctl start docker >> "$LOG_FILE" 2>&1
    systemctl enable docker >> "$LOG_FILE" 2>&1
    
    # Adicionar usuário atual ao grupo docker (se não for root)
    if [ -n "$SUDO_USER" ]; then
        print_step "Adicionando usuário $SUDO_USER ao grupo docker..."
        usermod -aG docker "$SUDO_USER" >> "$LOG_FILE" 2>&1
        print_warning "Faça logout e login novamente para usar Docker sem sudo"
    fi
    
    # Validação
    if command_exists docker && systemctl is-active --quiet docker; then
        local version=$(docker --version 2>&1)
        print_success "Docker instalado e ativo: $version"
        return 0
    else
        print_error "Falha na validação do Docker"
        return 1
    fi
}

#===============================================================================
# INSTALAÇÃO: HELM
#===============================================================================

install_helm() {
    print_header "INSTALANDO HELM"
    
    # Verificar se já está instalado
    if command_exists helm; then
        local current_version=$(helm version --short 2>&1 | head -1)
        print_warning "Helm já instalado (versão: $current_version)"
        read -p "Deseja reinstalar/atualizar? (s/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            print_status "Mantendo versão atual do Helm"
            return 0
        fi
    fi
    
    print_step "Baixando e instalando Helm..."
    
    cd /tmp
    
    # Usar script oficial de instalação
    if ! execute_with_retry "curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o get_helm.sh" "Download script Helm"; then
        print_error "Falha ao baixar script do Helm"
        return 1
    fi
    
    chmod 700 get_helm.sh
    
    if ! ./get_helm.sh >> "$LOG_FILE" 2>&1; then
        print_warning "Script oficial falhou, tentando instalação manual..."
        
        # Instalação manual como fallback
        local helm_version=$(curl -s https://api.github.com/repos/helm/helm/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
        helm_version=${helm_version:-v3.14.0}
        
        local helm_arch="amd64"
        [ "$ARCH" = "arm64" ] && helm_arch="arm64"
        
        curl -fsSL "https://get.helm.sh/helm-${helm_version}-linux-${helm_arch}.tar.gz" -o helm.tar.gz
        tar -zxvf helm.tar.gz >> "$LOG_FILE" 2>&1
        mv linux-${helm_arch}/helm /usr/local/bin/helm
        rm -rf linux-${helm_arch} helm.tar.gz
    fi
    
    rm -f /tmp/get_helm.sh
    
    # Validação
    if command_exists helm; then
        local version=$(helm version --short 2>&1 | head -1)
        print_success "Helm instalado: $version"
        return 0
    else
        print_error "Falha na validação do Helm"
        return 1
    fi
}

#===============================================================================
# INSTALAÇÃO: KUBECTL
#===============================================================================

install_kubectl() {
    print_header "INSTALANDO KUBECTL"
    
    # Verificar se já está instalado
    if command_exists kubectl; then
        local current_version=$(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | head -1 | awk '{print $2}')
        [ -z "$current_version" ] && current_version=$(kubectl version --client 2>&1 | head -1)
        print_warning "Kubectl já instalado (versão: $current_version)"
        read -p "Deseja reinstalar/atualizar? (s/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            print_status "Mantendo versão atual do Kubectl"
            return 0
        fi
    fi
    
    print_step "Obtendo última versão estável do kubectl..."
    
    local kubectl_version=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    
    if [ -z "$kubectl_version" ]; then
        print_warning "Não foi possível obter versão, usando v1.29.0"
        kubectl_version="v1.29.0"
    fi
    
    print_step "Baixando kubectl $kubectl_version..."
    
    local kubectl_arch="amd64"
    [ "$ARCH" = "arm64" ] && kubectl_arch="arm64"
    
    cd /tmp
    
    if ! execute_with_retry "curl -LO 'https://dl.k8s.io/release/${kubectl_version}/bin/linux/${kubectl_arch}/kubectl'" "Download kubectl"; then
        print_error "Falha ao baixar kubectl"
        return 1
    fi
    
    # Verificar checksum
    print_step "Verificando checksum..."
    curl -LO "https://dl.k8s.io/release/${kubectl_version}/bin/linux/${kubectl_arch}/kubectl.sha256" >> "$LOG_FILE" 2>&1
    
    if echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check >> "$LOG_FILE" 2>&1; then
        print_success "Checksum válido"
    else
        print_warning "Verificação de checksum falhou, mas continuando instalação..."
    fi
    
    # Instalar
    chmod +x kubectl
    mv kubectl /usr/local/bin/kubectl
    rm -f kubectl.sha256
    
    # Validação
    if command_exists kubectl; then
        local version=$(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | head -1 | awk '{print $2}')
        [ -z "$version" ] && version=$(kubectl version --client 2>&1 | head -1)
        print_success "Kubectl instalado: $version"
        
        # Configurar autocompletion
        print_step "Configurando bash completion..."
        kubectl completion bash > /etc/bash_completion.d/kubectl 2>/dev/null || true
        
        return 0
    else
        print_error "Falha na validação do kubectl"
        return 1
    fi
}

#===============================================================================
# INSTALAÇÃO: KUSTOMIZE
#===============================================================================

install_kustomize() {
    print_header "INSTALANDO KUSTOMIZE"
    
    # Verificar se já está instalado
    if command_exists kustomize; then
        local current_version=$(kustomize version --short 2>&1 | head -1)
        print_warning "Kustomize já instalado (versão: $current_version)"
        read -p "Deseja reinstalar/atualizar? (s/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            print_status "Mantendo versão atual do Kustomize"
            return 0
        fi
    fi
    
    print_step "Baixando e instalando Kustomize..."
    
    cd /tmp
    
    # Usar script oficial de instalação
    if ! execute_with_retry "curl -fsSL 'https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh' -o install_kustomize.sh" "Download script Kustomize"; then
        print_error "Falha ao baixar script do Kustomize"
        return 1
    fi
    
    chmod +x install_kustomize.sh
    
    if ! ./install_kustomize.sh >> "$LOG_FILE" 2>&1; then
        print_warning "Script oficial falhou, tentando instalação manual..."
        
        # Instalação manual como fallback
        local kustomize_version=$(curl -s https://api.github.com/repos/kubernetes-sigs/kustomize/releases | grep '"tag_name"' | grep 'kustomize/' | head -1 | cut -d'"' -f4 | cut -d'/' -f2)
        kustomize_version=${kustomize_version:-v5.3.0}
        
        local kustomize_arch="amd64"
        [ "$ARCH" = "arm64" ] && kustomize_arch="arm64"
        
        curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${kustomize_version}/kustomize_${kustomize_version}_linux_${kustomize_arch}.tar.gz" -o kustomize.tar.gz
        tar -zxvf kustomize.tar.gz >> "$LOG_FILE" 2>&1
        rm -f kustomize.tar.gz
    fi
    
    # Mover para path do sistema
    if [ -f /tmp/kustomize ]; then
        mv /tmp/kustomize /usr/local/bin/kustomize
        chmod +x /usr/local/bin/kustomize
    fi
    
    rm -f /tmp/install_kustomize.sh
    
    # Validação
    if command_exists kustomize; then
        local version=$(kustomize version 2>&1 | head -1)
        print_success "Kustomize instalado: $version"
        return 0
    else
        print_error "Falha na validação do Kustomize"
        return 1
    fi
}

#===============================================================================
# INSTALAÇÃO MANUAL: TERRAFORM (fallback)
#===============================================================================

install_terraform_manual() {
    print_step "Instalando Terraform manualmente..."
    
    cd /tmp
    rm -rf terraform terraform.zip
    
    # Obter última versão
    local tf_version=$(curl -s https://api.github.com/repos/hashicorp/terraform/releases/latest | grep '"tag_name"' | cut -d'"' -f4 | tr -d 'v')
    
    if [ -z "$tf_version" ]; then
        print_warning "Não foi possível obter versão, usando 1.7.0"
        tf_version="1.7.0"
    fi
    
    print_status "Baixando Terraform $tf_version..."
    
    local tf_arch="amd64"
    [ "$ARCH" = "arm64" ] && tf_arch="arm64"
    
    local tf_url="https://releases.hashicorp.com/terraform/${tf_version}/terraform_${tf_version}_linux_${tf_arch}.zip"
    
    if ! curl -fsSL "$tf_url" -o terraform.zip; then
        print_error "Falha ao baixar Terraform"
        return 1
    fi
    
    unzip -o terraform.zip >> "$LOG_FILE" 2>&1
    mv terraform /usr/local/bin/terraform
    chmod +x /usr/local/bin/terraform
    rm -f terraform.zip
    
    if command_exists terraform; then
        local version=$(terraform version 2>&1 | head -1)
        print_success "Terraform instalado manualmente: $version"
        return 0
    else
        print_error "Falha na instalação manual do Terraform"
        return 1
    fi
}

#===============================================================================
# INSTALAÇÃO: TERRAFORM
#===============================================================================

install_terraform() {
    print_header "INSTALANDO TERRAFORM CLI"
    
    # Verificar se já está instalado
    if command_exists terraform; then
        local current_version=$(terraform version 2>&1 | head -1)
        print_warning "Terraform já instalado ($current_version)"
        read -p "Deseja reinstalar/atualizar? (s/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            print_status "Mantendo versão atual do Terraform"
            return 0
        fi
    fi
    
    if [ "$OS_TYPE" = "debian" ]; then
        print_step "Configurando repositório HashiCorp para Debian/Ubuntu..."
        
        # Determinar a distribuição base para HashiCorp
        local hashicorp_codename=""
        
        case "$ID" in
            ubuntu|debian)
                hashicorp_codename=$(lsb_release -cs 2>/dev/null)
                ;;
            linuxmint)
                # Linux Mint precisa usar codename do Ubuntu base
                case "${VERSION_ID%%.*}" in
                    22) hashicorp_codename="noble" ;;
                    21) hashicorp_codename="jammy" ;;
                    20) hashicorp_codename="focal" ;;
                    *) hashicorp_codename="jammy" ;;
                esac
                print_status "Linux Mint $VERSION_ID mapeado para Ubuntu $hashicorp_codename"
                ;;
            *)
                hashicorp_codename="jammy"  # fallback seguro
                ;;
        esac
        
        # Adicionar chave GPG da HashiCorp
        rm -f /usr/share/keyrings/hashicorp-archive-keyring.gpg
        curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg 2>/dev/null
        
        # Adicionar repositório
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $hashicorp_codename main" > /etc/apt/sources.list.d/hashicorp.list
        
        apt-get update >> "$LOG_FILE" 2>&1
        
        print_step "Instalando Terraform..."
        if ! execute_with_retry "apt-get install -y terraform" "Instalar Terraform"; then
            print_warning "Falha ao instalar via repositório, tentando instalação manual..."
            install_terraform_manual
            return $?
        fi
        
    elif [ "$OS_TYPE" = "rhel" ]; then
        print_step "Configurando repositório HashiCorp para RHEL/Rocky..."
        
        # Adicionar repositório HashiCorp
        $PKG_MANAGER config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo >> "$LOG_FILE" 2>&1 || \
        curl -fsSL https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo -o /etc/yum.repos.d/hashicorp.repo
        
        print_step "Instalando Terraform..."
        if ! execute_with_retry "$PKG_MANAGER install -y terraform" "Instalar Terraform"; then
            print_warning "Falha ao instalar via repositório, tentando instalação manual..."
            install_terraform_manual
            return $?
        fi
    fi
    
    # Validação
    if command_exists terraform; then
        local version=$(terraform version 2>&1 | head -1)
        print_success "Terraform instalado: $version"
        
        # Habilitar autocompletion
        print_step "Configurando autocompletion..."
        terraform -install-autocomplete >> "$LOG_FILE" 2>&1 || true
        
        return 0
    else
        print_error "Falha na validação do Terraform"
        return 1
    fi
}

#===============================================================================
# INSTALAÇÃO: VSCODE
#===============================================================================

install_vscode() {
    print_header "INSTALANDO VISUAL STUDIO CODE"
    
    # Verificar se já está instalado (não pode usar code --version como root)
    local is_installed=false
    local current_version=""
    
    if [ "$OS_TYPE" = "debian" ]; then
        if dpkg -s code &>/dev/null; then
            is_installed=true
            current_version=$(dpkg -s code 2>/dev/null | grep "^Version:" | cut -d' ' -f2)
        fi
    elif [ "$OS_TYPE" = "rhel" ]; then
        if rpm -q code &>/dev/null; then
            is_installed=true
            current_version=$(rpm -q code --queryformat '%{VERSION}' 2>/dev/null)
        fi
    fi
    
    if $is_installed; then
        print_warning "VS Code já instalado (versão: $current_version)"
        read -p "Deseja reinstalar/atualizar? (s/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            print_status "Mantendo versão atual do VS Code"
            return 0
        fi
    fi
    
    if [ "$OS_TYPE" = "debian" ]; then
        print_step "Configurando repositório Microsoft para Debian/Ubuntu..."
        
        # Adicionar chave GPG da Microsoft
        curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/packages.microsoft.gpg 2>/dev/null
        
        # Adicionar repositório
        echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
        
        apt-get update >> "$LOG_FILE" 2>&1
        
        print_step "Instalando VS Code..."
        if ! execute_with_retry "apt-get install -y code" "Instalar VS Code"; then
            print_error "Falha ao instalar VS Code via apt"
            return 1
        fi
        
    elif [ "$OS_TYPE" = "rhel" ]; then
        print_step "Configurando repositório Microsoft para RHEL/Rocky..."
        
        # Importar chave GPG da Microsoft
        rpm --import https://packages.microsoft.com/keys/microsoft.asc >> "$LOG_FILE" 2>&1
        
        # Adicionar repositório
        cat > /etc/yum.repos.d/vscode.repo << 'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
        
        print_step "Instalando VS Code..."
        if ! execute_with_retry "$PKG_MANAGER install -y code" "Instalar VS Code"; then
            print_error "Falha ao instalar VS Code via $PKG_MANAGER"
            return 1
        fi
    fi
    
    # Validação - VS Code não pode ser executado como root
    local vscode_installed=false
    local version=""
    
    if [ "$OS_TYPE" = "debian" ]; then
        if dpkg -s code &>/dev/null; then
            vscode_installed=true
            version=$(dpkg -s code 2>/dev/null | grep "^Version:" | cut -d' ' -f2)
        fi
    elif [ "$OS_TYPE" = "rhel" ]; then
        if rpm -q code &>/dev/null; then
            vscode_installed=true
            version=$(rpm -q code --queryformat '%{VERSION}' 2>/dev/null)
        fi
    fi
    
    if $vscode_installed; then
        print_success "VS Code instalado: versão $version"
        
        # Criar atalho no desktop se houver GUI
        if $HAS_GUI; then
            create_vscode_desktop_shortcut
        fi
        
        return 0
    else
        print_error "Falha na validação do VS Code"
        return 1
    fi
}

#===============================================================================
# CRIAR ATALHO DO VSCODE NO DESKTOP
#===============================================================================

create_vscode_desktop_shortcut() {
    if [ -z "$DESKTOP_PATH" ] || [ -z "$SUDO_USER" ]; then
        print_warning "Não foi possível determinar o caminho do Desktop"
        return 1
    fi
    
    print_step "Criando atalho do VS Code no Desktop..."
    
    local desktop_file="$DESKTOP_PATH/code.desktop"
    
    # Criar arquivo .desktop
    cat > "$desktop_file" << 'EOF'
[Desktop Entry]
Name=Visual Studio Code
Comment=Code Editing. Redefined.
GenericName=Text Editor
Exec=/usr/bin/code --unity-launch %F
Icon=vscode
Type=Application
StartupNotify=true
StartupWMClass=Code
Categories=TextEditor;Development;IDE;
MimeType=text/plain;inode/directory;application/x-code-workspace;
Actions=new-empty-window;
Keywords=vscode;

[Desktop Action new-empty-window]
Name=New Empty Window
Exec=/usr/bin/code --new-window %F
Icon=vscode
EOF
    
    # Definir permissões corretas
    chmod +x "$desktop_file"
    chown "$SUDO_USER:$SUDO_USER" "$desktop_file"
    
    # Marcar como confiável (GNOME)
    if command_exists gio; then
        sudo -u "$SUDO_USER" gio set "$desktop_file" metadata::trusted true 2>/dev/null || true
    fi
    
    # Verificar se o arquivo foi criado
    if [ -f "$desktop_file" ]; then
        print_success "Atalho do VS Code criado em: $desktop_file"
        return 0
    else
        print_warning "Não foi possível criar atalho do VS Code"
        return 1
    fi
}

#===============================================================================
# INSTALAÇÃO: ZOOM
#===============================================================================

install_zoom() {
    print_header "INSTALANDO ZOOM"
    
    # Verificar se há GUI
    if ! $HAS_GUI; then
        print_warning "Zoom requer ambiente gráfico"
        print_status "Sistema detectado como servidor (sem GUI). Pulando instalação do Zoom."
        return 0
    fi
    
    # Verificar se já está instalado
    if command_exists zoom; then
        local current_version=$(zoom --version 2>&1 | head -1 || echo "instalado")
        print_warning "Zoom já instalado ($current_version)"
        read -p "Deseja reinstalar/atualizar? (s/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            print_status "Mantendo versão atual do Zoom"
            return 0
        fi
    fi
    
    cd /tmp
    rm -f zoom*.deb zoom*.rpm
    
    if [ "$OS_TYPE" = "debian" ]; then
        print_step "Baixando Zoom para Debian/Ubuntu..."
        
        local zoom_url="https://zoom.us/client/latest/zoom_amd64.deb"
        [ "$ARCH" = "arm64" ] && zoom_url="https://zoom.us/client/latest/zoom_arm64.deb"
        
        if ! execute_with_retry "curl -fsSL '$zoom_url' -o zoom.deb" "Download Zoom"; then
            print_error "Falha ao baixar Zoom"
            return 1
        fi
        
        print_step "Instalando dependências do Zoom..."
        # Instalar dependências comuns do Zoom
        apt-get install -y libxcb-xtest0 libxcb-xinerama0 libxcb-cursor0 \
            libglib2.0-0 libxcb-keysyms1 libxcb-randr0 libxcb-shape0 \
            libxcb-xfixes0 libxcb-shm0 libxcb-render-util0 libxcb-image0 \
            libxcb-icccm4 libxkbcommon-x11-0 libgl1 libegl1 \
            libpulse0 libxcomposite1 2>/dev/null || true
        
        print_step "Instalando Zoom..."
        if ! dpkg -i zoom.deb >> "$LOG_FILE" 2>&1; then
            print_status "Corrigindo dependências..."
            apt-get install -f -y >> "$LOG_FILE" 2>&1
            
            # Tentar instalar novamente
            if ! dpkg -i zoom.deb >> "$LOG_FILE" 2>&1; then
                print_error "Falha ao instalar Zoom"
                rm -f zoom.deb
                return 1
            fi
        fi
        
        rm -f zoom.deb
        
    elif [ "$OS_TYPE" = "rhel" ]; then
        print_step "Baixando Zoom para RHEL/Rocky..."
        
        local zoom_url="https://zoom.us/client/latest/zoom_x86_64.rpm"
        [ "$ARCH" = "arm64" ] && zoom_url="https://zoom.us/client/latest/zoom_aarch64.rpm"
        
        if ! execute_with_retry "curl -fsSL '$zoom_url' -o zoom.rpm" "Download Zoom"; then
            print_error "Falha ao baixar Zoom"
            return 1
        fi
        
        print_step "Instalando dependências do Zoom..."
        # Instalar dependências comuns do Zoom para RHEL
        $PKG_MANAGER install -y libxcb xcb-util-wm xcb-util-image \
            xcb-util-keysyms xcb-util-renderutil mesa-libGL mesa-libEGL \
            pulseaudio-libs libxkbcommon-x11 libXcomposite 2>/dev/null || true
        
        print_step "Instalando Zoom..."
        if ! $PKG_MANAGER localinstall -y zoom.rpm >> "$LOG_FILE" 2>&1; then
            print_error "Falha ao instalar Zoom"
            rm -f zoom.rpm
            return 1
        fi
        
        rm -f zoom.rpm
    fi
    
    # Criar atalho no desktop
    if [ -n "$DESKTOP_PATH" ] && [ -n "$SUDO_USER" ]; then
        create_zoom_desktop_shortcut
    fi
    
    # Validação
    if command_exists zoom || [ -f /usr/bin/zoom ]; then
        print_success "Zoom instalado com sucesso"
        return 0
    else
        print_error "Falha na validação do Zoom"
        return 1
    fi
}

#===============================================================================
# CRIAR ATALHO DO ZOOM NO DESKTOP
#===============================================================================

create_zoom_desktop_shortcut() {
    if [ -z "$DESKTOP_PATH" ] || [ -z "$SUDO_USER" ]; then
        return 1
    fi
    
    print_step "Criando atalho do Zoom no Desktop..."
    
    local desktop_file="$DESKTOP_PATH/Zoom.desktop"
    
    # Verificar se já existe um .desktop do Zoom no sistema
    if [ -f /usr/share/applications/Zoom.desktop ]; then
        cp /usr/share/applications/Zoom.desktop "$desktop_file"
    elif [ -f /usr/share/applications/zoom.desktop ]; then
        cp /usr/share/applications/zoom.desktop "$desktop_file"
    else
        # Criar manualmente
        cat > "$desktop_file" << 'EOF'
[Desktop Entry]
Name=Zoom
Comment=Zoom Video Conference
GenericName=Video Conference
Exec=/usr/bin/zoom %U
Icon=Zoom
Type=Application
StartupNotify=true
Terminal=false
Categories=Network;Application;
MimeType=x-scheme-handler/zoommtg;x-scheme-handler/zoomus;x-scheme-handler/tel;x-scheme-handler/callto;x-scheme-handler/zoomphonecall;application/x-zoom;
Keywords=zoom;video;conference;meeting;
EOF
    fi
    
    # Definir permissões corretas
    chmod +x "$desktop_file"
    chown "$SUDO_USER:$SUDO_USER" "$desktop_file"
    
    # Marcar como confiável (GNOME)
    if command_exists gio; then
        sudo -u "$SUDO_USER" gio set "$desktop_file" metadata::trusted true 2>/dev/null || true
    fi
    
    if [ -f "$desktop_file" ]; then
        print_success "Atalho do Zoom criado em: $desktop_file"
        return 0
    else
        print_warning "Não foi possível criar atalho do Zoom"
        return 1
    fi
}

#===============================================================================
# RELATÓRIO FINAL
#===============================================================================

generate_report() {
    print_header "RELATÓRIO DE INSTALAÇÃO"
    
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC}                    FERRAMENTAS INSTALADAS                       ${CYAN}│${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────────┤${NC}"
    
    local tools=("aws" "docker" "helm" "kubectl" "kustomize" "terraform" "code" "zoom")
    local names=("AWS CLI" "Docker" "Helm" "Kubectl" "Kustomize" "Terraform" "VS Code" "Zoom")
    
    for i in "${!tools[@]}"; do
        local tool="${tools[$i]}"
        local name="${names[$i]}"
        
        if command_exists "$tool" || [ -f "/usr/bin/$tool" ]; then
            local version=""
            case "$tool" in
                aws)       version=$(aws --version 2>&1 | cut -d' ' -f1 | cut -d'/' -f2) ;;
                docker)    version=$(docker --version 2>&1 | cut -d' ' -f3 | tr -d ',') ;;
                helm)      version=$(helm version --short 2>&1 | head -1) ;;
                kubectl)   version=$(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | head -1 | cut -d':' -f2 | tr -d ' "' || kubectl version --client 2>&1 | grep "Client Version" | head -1) ;;
                kustomize) version=$(kustomize version 2>&1 | head -1) ;;
                terraform) version=$(terraform version 2>&1 | head -1 | cut -d' ' -f2) ;;
                code)      
                    # VS Code não pode ser executado como root, verificar via dpkg/rpm
                    if [ "$OS_TYPE" = "debian" ]; then
                        version=$(dpkg -s code 2>/dev/null | grep "^Version:" | cut -d' ' -f2)
                    else
                        version=$(rpm -q code --queryformat '%{VERSION}' 2>/dev/null)
                    fi
                    [ -z "$version" ] && version="instalado"
                    ;;
                zoom)      
                    if [ "$OS_TYPE" = "debian" ]; then
                        version=$(dpkg -s zoom 2>/dev/null | grep "^Version:" | cut -d' ' -f2)
                    else
                        version=$(rpm -q zoom --queryformat '%{VERSION}' 2>/dev/null)
                    fi
                    [ -z "$version" ] && version="instalado"
                    ;;
            esac
            printf "${CYAN}│${NC} ${GREEN}✓${NC} %-15s │ %-40s ${CYAN}│${NC}\n" "$name" "$version"
        else
            printf "${CYAN}│${NC} ${RED}✗${NC} %-15s │ %-40s ${CYAN}│${NC}\n" "$name" "NÃO INSTALADO"
        fi
    done
    
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────────┤${NC}"
    
    # Informação sobre GUI
    if $HAS_GUI; then
        printf "${CYAN}│${NC} ${GREEN}●${NC} %-15s │ %-40s ${CYAN}│${NC}\n" "Ambiente GUI" "DETECTADO"
        if [ -n "$DESKTOP_PATH" ]; then
            printf "${CYAN}│${NC}   %-15s │ %-40s ${CYAN}│${NC}\n" "Desktop" "$DESKTOP_PATH"
        fi
    else
        printf "${CYAN}│${NC} ${YELLOW}●${NC} %-15s │ %-40s ${CYAN}│${NC}\n" "Ambiente GUI" "Não detectado (Servidor)"
    fi
    
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────────┘${NC}"
    
    echo ""
    echo -e "${YELLOW}NOTAS IMPORTANTES:${NC}"
    echo -e "  • Log completo disponível em: ${BLUE}$LOG_FILE${NC}"
    echo -e "  • Se instalou Docker, faça logout/login para usar sem sudo"
    echo -e "  • Execute 'source ~/.bashrc' para ativar autocompletions"
    if $HAS_GUI && [ -n "$DESKTOP_PATH" ]; then
        echo -e "  • Atalhos criados em: ${BLUE}$DESKTOP_PATH${NC}"
    fi
    echo ""
}

#===============================================================================
# MENU INTERATIVO
#===============================================================================

show_menu() {
    print_header "DEVOPS TOOLS INSTALLER"
    
    echo -e "Sistema: ${GREEN}$PRETTY_NAME${NC}"
    echo -e "Arquitetura: ${GREEN}$ARCH${NC}"
    if $HAS_GUI; then
        echo -e "Ambiente Gráfico: ${GREEN}Detectado${NC}"
    else
        echo -e "Ambiente Gráfico: ${YELLOW}Não detectado (Servidor)${NC}"
    fi
    echo ""
    echo -e "Selecione uma opção:"
    echo ""
    echo -e "  ${CYAN}1)${NC} Instalar TODAS as ferramentas"
    echo -e "  ${CYAN}2)${NC} AWS CLI"
    echo -e "  ${CYAN}3)${NC} Docker"
    echo -e "  ${CYAN}4)${NC} Helm"
    echo -e "  ${CYAN}5)${NC} Kubectl"
    echo -e "  ${CYAN}6)${NC} Kustomize"
    echo -e "  ${CYAN}7)${NC} Terraform"
    echo -e "  ${CYAN}8)${NC} VS Code"
    if $HAS_GUI; then
        echo -e "  ${CYAN}9)${NC} Zoom (Videoconferência)"
    else
        echo -e "  ${YELLOW}9)${NC} Zoom (Requer GUI)"
    fi
    echo -e "  ${CYAN}R)${NC} Gerar relatório de status"
    echo -e "  ${CYAN}0)${NC} Sair"
    echo ""
}

#===============================================================================
# FUNÇÃO PRINCIPAL
#===============================================================================

main() {
    # Criar arquivo de log
    touch "$LOG_FILE" 2>/dev/null || true
    
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}           ${GREEN}DevOps Tools Installer v1.1${NC}                           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}           Ubuntu / Debian / Rocky Linux / RHEL                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Verificar root
    check_root
    
    # Detectar OS
    detect_os
    
    # Detectar GUI
    detect_gui
    
    # Verificar se foi passado argumento
    if [ $# -gt 0 ]; then
        case "$1" in
            --all|-a)
                prepare_system
                install_awscli
                install_docker
                install_helm
                install_kubectl
                install_kustomize
                install_terraform
                install_vscode
                install_zoom
                generate_report
                exit 0
                ;;
            --help|-h)
                echo "Uso: $0 [OPÇÃO]"
                echo ""
                echo "Opções:"
                echo "  --all, -a     Instalar todas as ferramentas"
                echo "  --help, -h    Mostrar esta ajuda"
                echo ""
                echo "Ferramentas instaladas:"
                echo "  - AWS CLI"
                echo "  - Docker"
                echo "  - Helm"
                echo "  - Kubectl"
                echo "  - Kustomize"
                echo "  - Terraform"
                echo "  - VS Code (com atalho no Desktop se GUI detectado)"
                echo "  - Zoom (apenas se GUI detectado)"
                echo ""
                echo "Sem argumentos, o script iniciará em modo interativo."
                exit 0
                ;;
        esac
    fi
    
    # Menu interativo
    while true; do
        show_menu
        read -p "Opção: " choice
        
        case $choice in
            1)
                prepare_system
                install_awscli
                install_docker
                install_helm
                install_kubectl
                install_kustomize
                install_terraform
                install_vscode
                install_zoom
                generate_report
                ;;
            2) prepare_system; install_awscli ;;
            3) prepare_system; install_docker ;;
            4) prepare_system; install_helm ;;
            5) prepare_system; install_kubectl ;;
            6) prepare_system; install_kustomize ;;
            7) prepare_system; install_terraform ;;
            8) prepare_system; install_vscode ;;
            9) prepare_system; install_zoom ;;
            [Rr]) generate_report ;;
            0)
                echo -e "\n${GREEN}Até logo!${NC}\n"
                exit 0
                ;;
            *)
                print_error "Opção inválida"
                ;;
        esac
        
        echo ""
        read -p "Pressione ENTER para continuar..."
    done
}

# Executar
main "$@"
