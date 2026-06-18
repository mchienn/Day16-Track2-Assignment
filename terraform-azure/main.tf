resource "random_id" "id" {
  byte_length = 4
}

# 1. Resource Group
resource "azurerm_resource_group" "ai_rg" {
  name     = "${var.resource_group_name}-${random_id.id.hex}"
  location = var.location
}

# 2. Virtual Network
resource "azurerm_virtual_network" "ai_vnet" {
  name                = "ai-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.ai_rg.location
  resource_group_name = azurerm_resource_group.ai_rg.name
}

# 3. Public Subnet (for Bastion)
resource "azurerm_subnet" "public" {
  name                 = "public-subnet"
  resource_group_name  = azurerm_resource_group.ai_rg.name
  virtual_network_name = azurerm_virtual_network.ai_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# 4. Private Subnet (for GPU Node)
resource "azurerm_subnet" "private" {
  name                 = "private-subnet"
  resource_group_name  = azurerm_resource_group.ai_rg.name
  virtual_network_name = azurerm_virtual_network.ai_vnet.name
  address_prefixes     = ["10.0.2.0/24"]

  delegation {
    name = "gpu-delegation"
    service_delegation {
      name = "Microsoft.Network/virtualNetworks"
    }
  }
}

# 5. Public IP for Bastion
resource "azurerm_public_ip" "bastion_pip" {
  name                = "bastion-pip"
  location            = azurerm_resource_group.ai_rg.location
  resource_group_name = azurerm_resource_group.ai_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# 6. Public IP for Load Balancer
resource "azurerm_public_ip" "lb_pip" {
  name                = "lb-pip"
  location            = azurerm_resource_group.ai_rg.location
  resource_group_name = azurerm_resource_group.ai_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# 7. Network Security Group - Bastion
resource "azurerm_network_security_group" "bastion_nsg" {
  name                = "bastion-nsg"
  location            = azurerm_resource_group.ai_rg.location
  resource_group_name = azurerm_resource_group.ai_rg.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# 8. Network Security Group - GPU Node
resource "azurerm_network_security_group" "gpu_nsg" {
  name                = "gpu-nsg"
  location            = azurerm_resource_group.ai_rg.location
  resource_group_name = azurerm_resource_group.ai_rg.name

  security_rule {
    name                       = "AllowSSHFromBastion"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPFromLB"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8000"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
}

# 9. NSG Association - Public Subnet
resource "azurerm_subnet_network_security_group_association" "public_nsg" {
  subnet_id                 = azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.bastion_nsg.id
}

# 10. NSG Association - Private Subnet
resource "azurerm_subnet_network_security_group_association" "private_nsg" {
  subnet_id                 = azurerm_subnet.private.id
  network_security_group_id = azurerm_network_security_group.gpu_nsg.id
}

# 11. NAT Gateway (for private subnet outbound)
resource "azurerm_public_ip" "nat_pip" {
  name                = "nat-pip"
  location            = azurerm_resource_group.ai_rg.location
  resource_group_name = azurerm_resource_group.ai_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_nat_gateway" "nat" {
  name                = "ai-nat-gateway"
  location            = azurerm_resource_group.ai_rg.location
  resource_group_name = azurerm_resource_group.ai_rg.name
  sku_name            = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "nat_pip_assoc" {
  nat_gateway_id       = azurerm_nat_gateway.nat.id
  public_ip_address_id = azurerm_public_ip.nat_pip.id
}

resource "azurerm_subnet_nat_gateway_association" "private_nat" {
  subnet_id      = azurerm_subnet.private.id
  nat_gateway_id = azurerm_nat_gateway.nat.id
}

# 12. Bastion Host (Jump Box)
resource "azurerm_network_interface" "bastion_nic" {
  name                = "bastion-nic"
  location            = azurerm_resource_group.ai_rg.location
  resource_group_name = azurerm_resource_group.ai_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.public.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.bastion_pip.id
  }
}

resource "azurerm_linux_virtual_machine" "bastion" {
  name                = "ai-bastion-host"
  resource_group_name = azurerm_resource_group.ai_rg.name
  location            = azurerm_resource_group.ai_rg.location
  size                = "Standard_B2s"
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.bastion_nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

# 13. GPU Node (Private)
resource "azurerm_network_interface" "gpu_nic" {
  name                = "gpu-nic"
  location            = azurerm_resource_group.ai_rg.location
  resource_group_name = azurerm_resource_group.ai_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.private.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "gpu_node" {
  name                = "ai-gpu-node"
  resource_group_name = azurerm_resource_group.ai_rg.name
  location            = azurerm_resource_group.ai_rg.location
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.gpu_nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 150
  }

  source_image_reference {
    publisher = "nvidia"
    offer     = "gpu-cloud-init"
    sku       = "nvidia-t4-pytorch-2204"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/user_data.sh", {
    hf_token = var.hf_token
    model_id = var.model_id
  }))
}

# 14. Load Balancer
resource "azurerm_lb" "ai_lb" {
  name                = "ai-inference-lb"
  location            = azurerm_resource_group.ai_rg.location
  resource_group_name = azurerm_resource_group.ai_rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "public"
    public_ip_address_id = azurerm_public_ip.lb_pip.id
  }
}

resource "azurerm_lb_backend_address_pool" "ai_pool" {
  loadbalancer_id = azurerm_lb.ai_lb.id
  name            = "gpu-backend-pool"
}

resource "azurerm_network_interface_backend_address_pool_association" "gpu_lb" {
  network_interface_id    = azurerm_network_interface.gpu_nic.id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.ai_pool.id
}

resource "azurerm_lb_probe" "vllm_probe" {
  loadbalancer_id = azurerm_lb.ai_lb.id
  name            = "vllm-health"
  port            = 8000
  protocol        = "Http"
  request_path    = "/health"
}

resource "azurerm_lb_rule" "vllm_rule" {
  loadbalancer_id                = azurerm_lb.ai_lb.id
  name                           = "vllm-rule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 8000
  frontend_ip_configuration_name = "public"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.ai_pool.id]
  probe_id                       = azurerm_lb_probe.vllm_probe.id
}
