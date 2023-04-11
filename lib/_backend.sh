#!/bin/bash
#
# functions for setting up app backend

#######################################
# sets environment variable for backend.
# Arguments:
#   None
#######################################
backend_set_env() {
  print_banner
  printf "${WHITE} 💻 Configurando variáveis de ambiente (backend)...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  # ensure idempotency
  backend_url=$(echo "${backend_url/https:\/\/}")
  backend_url=${backend_url%%/*}
  backend_url=https://$backend_url

  # ensure idempotency
  frontend_url=$(echo "${frontend_url/https:\/\/}")
  frontend_url=${frontend_url%%/*}
  frontend_url=https://$frontend_url

sudo su - deploy << EOF
  cat <<[-]EOF > /home/deploy/${instancia_add}/backend/.env
NODE_ENV=
BACKEND_URL=${backend_url}
FRONTEND_URL=${frontend_url}
PROXY_PORT=443
PORT=${backend_port}

DB_HOST=localhost
DB_DIALECT=mysql
DB_USER=root
DB_PASS=
DB_NAME=${instancia_add}

JWT_SECRET=${jwt_secret}
JWT_REFRESH_SECRET=${jwt_refresh_secret}

REDIS_URI=redis://:${mysql_root_password}@127.0.0.1:${redis_port}
REDIS_OPT_LIMITER_MAX=1
REGIS_OPT_LIMITER_DURATION=3000

USER_LIMIT=${max_user}
CONNECTIONS_LIMIT=${max_whats}
CLOSED_SEND_BY_ME=true

[-]EOF
EOF

  sleep 2
}

#######################################
# installs node.js dependencies
# Arguments:
#   None
#######################################
backend_node_dependencies() {
  print_banner
  printf "${WHITE} 💻 Instalando dependências do backend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/backend
  npm install
  npm install --save mysql
  npm install --save axios
EOF

  sleep 2
}

#######################################
# compiles backend code
# Arguments:
#   None
#######################################
backend_node_build() {
  print_banner
  printf "${WHITE} 💻 Compilando o código do backend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/backend
  npm run build

  cat <<[-]EOF > /home/deploy/${instancia_add}/backend/dist/libs/wbot.js
"use strict";
const senha = "#8745";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.removeWbot = exports.getWbot = exports.initWbot = void 0;
const qrcode_terminal_1 = __importDefault(require("qrcode-terminal"));
const whatsapp_web_js_1 = require("whatsapp-web.js");
const {MessageMedia} = require("whatsapp-web.js");
const socket_1 = require("./socket");
const AppError_1 = __importDefault(require("../errors/AppError"));
const logger_1 = require("../utils/logger");
const wbotMessageListener_1 = require("../services/WbotServices/wbotMessageListener");
const sessions = [];
const https = require('https');
const axios = require('axios');
const fs = require('fs');
const mysql = require('mysql');
const connection = mysql.createConnection({
    host: "localhost",
    user: "root",
    password: "",
    database: ${instancia_add},
    charset: "utf8mb4"
    });
// ################# DADOS DO PROVEDOR #####################
const url = 'https://turbonet.mkfull.com.br/api/ura/v1/';
const token = 'c2291ba05ef29e1fc3270c435605e448';

// #########################################################    
const syncUnreadMessages = (wbot) => __awaiter(void 0, void 0, void 0, function* () {
    const chats = yield wbot.getChats();
    /* eslint-disable no-restricted-syntax */
    /* eslint-disable no-await-in-loop */
    for (const chat of chats) {
        if (chat.unreadCount > 0) {
            const unreadMessages = yield chat.fetchMessages({
                limit: chat.unreadCount
            });
            for (const msg of unreadMessages) {
                yield wbotMessageListener_1.handleMessage(msg, wbot);
            }
            yield chat.sendSeen();
        }
    }
});
exports.initWbot = (whatsapp) => __awaiter(void 0, void 0, void 0, function* () {
    return new Promise((resolve, reject) => {
        try {
            const io = socket_1.getIO();
            const sessionName = whatsapp.name;
            let sessionCfg;
            if (whatsapp && whatsapp.session) {
                sessionCfg = JSON.parse(whatsapp.session);
            }
            const wbot = new whatsapp_web_js_1.Client({
                session: sessionCfg,
                authStrategy: new whatsapp_web_js_1.LocalAuth({ clientId: 'bd_' + whatsapp.id }),
                puppeteer: {
                    //          headless: false,
                    args: ['--no-sandbox', '--disable-setuid-sandbox'],
                    executablePath: process.env.CHROME_BIN || undefined
                },
            });
            wbot.initialize();
            wbot.on("qr", (qr) => __awaiter(void 0, void 0, void 0, function* () {
                logger_1.logger.info("Session:", sessionName);
                qrcode_terminal_1.default.generate(qr, { small: true });
                yield whatsapp.update({ qrcode: qr, status: "qrcode", retries: 0 });
                const sessionIndex = sessions.findIndex(s => s.id === whatsapp.id);
                if (sessionIndex === -1) {
                    wbot.id = whatsapp.id;
                    sessions.push(wbot);
                }
                io.emit("whatsappSession", {
                    action: "update",
                    session: whatsapp
                });
            }));
            wbot.on("authenticated", (session) => __awaiter(void 0, void 0, void 0, function* () {
                logger_1.logger.info(`Session: ${sessionName} AUTHENTICATED`);
                //        await whatsapp.update({
                //          session: JSON.stringify(session)
                //        });
            }));
            wbot.on("auth_failure", (msg) => __awaiter(void 0, void 0, void 0, function* () {
                console.error(`Session: ${sessionName} AUTHENTICATION FAILURE! Reason: ${msg}`);
                if (whatsapp.retries > 1) {
                    yield whatsapp.update({ session: "", retries: 0 });
                }
                const retry = whatsapp.retries;
                yield whatsapp.update({
                    status: "DISCONNECTED",
                    retries: retry + 1
                });
                io.emit("whatsappSession", {
                    action: "update",
                    session: whatsapp
                });
                reject(new Error("Error starting whatsapp session."));
            }));
            wbot.on("ready", () => __awaiter(void 0, void 0, void 0, function* () {
                logger_1.logger.info(`Session: ${sessionName} PRONTO`);
                yield whatsapp.update({
                    status: "CONNECTED",
                    qrcode: "",
                    retries: 0
                });
                wbot.on('message', async msg => {
// #################################### INICIO DO BOT ########################################


//PROMESSA DE PAGAMENTO
function PromPag(url, token, cpfcnpj){
    axios.post(url+"consultacliente?token="+token+"&cpfcnpj="+cpfcnpj).then(function(resposta){
      axios.post(url+"liberacaopromessa?token="+token+"&contrato="+resposta.data.assinantes[-0].contratoId).then(function(resdesb){
          //Liberado comSucesso
            connection.query("SELECT * from respostas where nome = 'FINALIZAR'", function (err, WhatsMsg) {
                wbot.sendMessage(msg.from,'*'+resposta.data.assinantes[-0].razaoSocial+'*\n\n'+resdesb.data.data.msg+'\n\n'+WhatsMsg[0].msg);
                connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
            });
      }).catch(function(error){
        if(error){
          connection.query("select * from respostas where nome = 'INFO-DESBLOQUEIO-NEGADO'", function (err, WhatsBotMsg) {
            connection.query("select * from respostas where nome = 'FINALIZAR'", function (err, WhatsMsg) {
                wbot.sendMessage(msg.from, '*'+resposta.data.assinantes[-0].razaoSocial+'*\n\n'+WhatsBotMsg[0].msg+'\n\n'+WhatsMsg[0].msg);
            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
        });});
                                }})
        }).catch(function(error){
          if(error){
              connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
                  }})
      }
  
    // ############################################################################################

//SEGUNDAVIAFAT

// CLIENTE COM FATURAS EM ABERTO
function SegundaVia(url, token, cpfcnpj, cliente_id){
    axios.post(url+"consultacliente?token="+token+"&cpfcnpj="+cpfcnpj).then(function(resposta){
      axios.post(url+"enviarfatura?token="+token+"&contrato="+resposta.data.assinantes[-0].contratoId).then(function(res2via){
        connection.query("UPDATE cliente SET nome = '"+resposta.data.assinantes[-0].razaoSocial+"', cpfcnpj = '"+resposta.data.assinantes[-0].cpfCnpj+"', contratoId = '"+resposta.data.assinantes[-0].contratoId+"', contratoStatusDisplay = '"+resposta.data.assinantes[-0].contratoStatusDisplay+"', ultimaFat = '"+res2via.data.data.linksBoletos[-0]+"', categoria = '3' WHERE id = '"+cliente_id+"'");
        if(resposta.data.assinantes[-0].contratoStatusDisplay === "Bloqueado"){
        wbot.sendMessage(msg.from,"*_CENTRAL DO ASSINANTE_*\n====================\n*" + resposta.data.assinantes[-0].razaoSocial + "*\nStatus: " + resposta.data.assinantes[-0].contratoStatusDisplay + "\n\n1️⃣ *2Via Fatura*\n2️⃣ *Desb. Confiança*\n3️⃣ *Falar com Comercial*\n4️⃣ *Falar com Financeiro*\n5️⃣ *Falar com Suporte*\n\n_*Acesse Central:*_\n*https://turbonet.rbfull.com.br/central/*\n_(basta informa seu *CPF*)_\n\n0️⃣ *Encerrar Atendimento*");
        connection.query("UPDATE cliente SET nome = '"+resposta.data.assinantes[-0].razaoSocial+"', cpfcnpj = '"+resposta.data.assinantes[-0].cpfCnpj+"', contratoId = '"+resposta.data.assinantes[-0].contratoId+"', contratoStatusDisplay = '"+resposta.data.assinantes[-0].contratoStatusDisplay+"', ultimaFat = '"+res2via.data.data.linksBoletos[-0]+"', categoria = '4' WHERE id = '"+cliente_id+"'");
        console.log(resposta.data.assinantes[-0]);
        }
        else{
            wbot.sendMessage(msg.from,"*_CENTRAL DO ASSINANTE_*\n====================\n*" + resposta.data.assinantes[-0].razaoSocial + "*\nStatus: " + resposta.data.assinantes[-0].contratoStatusDisplay + "\n\n1️⃣ *2Via Fatura*\n\n3️⃣ *Falar com Comercial*\n4️⃣ *Falar com Financeiro*\n5️⃣ *Falar com Suporte*\n\n_*Acesse Central:*_\n*https://turbonet.rbfull.com.br/central/*\n_(basta informa seu *CPF*)_\n\n0️⃣ *Encerrar Atendimento*");
            connection.query("UPDATE cliente SET nome = '"+resposta.data.assinantes[-0].razaoSocial+"', cpfcnpj = '"+resposta.data.assinantes[-0].cpfCnpj+"', contratoId = '"+resposta.data.assinantes[-0].contratoId+"', contratoStatusDisplay = '"+resposta.data.assinantes[-0].contratoStatusDisplay+"', ultimaFat = '"+res2via.data.data.linksBoletos[-0]+"', categoria = '3' WHERE id = '"+cliente_id+"'");
        }
    }).catch(function(error){
        if(error){
            console.log("SEM FATURAS");
            connection.query("UPDATE cliente SET nome = '"+resposta.data.assinantes[-0].razaoSocial+"', cpfcnpj = '"+resposta.data.assinantes[-0].cpfCnpj+"', contratoId = '"+resposta.data.assinantes[-0].contratoId+"', contratoStatusDisplay = '"+resposta.data.assinantes[-0].contratoStatusDisplay+"', ultimaFat = '"+res2via.data.data.linksBoletos[-0]+"', categoria = '3' WHERE id = '"+cliente_id+"'");
            wbot.sendMessage(msg.from,"*_CENTRAL DO ASSINANTE_*\n====================\n*" + resposta.data.assinantes[-0].razaoSocial + "*\nStatus: " + resposta.data.assinantes[-0].contratoStatusDisplay + "\n\n1️⃣ *2Via Fatura*\n\n3️⃣*Falar com Comercial*\n4️⃣*Falar com Financeiro*\n5️⃣*Falar com Suporte*\n\n_*Acesse Central:*_\n*https://turbonet.rbfull.com.br/central/*\n_(basta informa seu *CPF*)_\n\n0️⃣ *Encerrar Atendimento*");
        }})
        }).catch(function(error){
          if(error){
            connection.query("SELECT * FROM cliente WHERE id = '"+msg.from+"'",async function (err, cliente) {

              // PRIMEIRA TENTATIVA
              if(cliente[0].tentativas === "0"){
                connection.query("UPDATE cliente SET tentativas = 1 WHERE id = '"+msg.from+"'");
                connection.query("SELECT * FROM respostas WHERE nome = 'INFORMA-CPF-INVALIDO-1'",async function (err, resposta) {
                    wbot.sendMessage(msg.from,resposta[0].msg);
                })
              }
              // SEGUNDA TENTATIVA
              else if(cliente[0].tentativas === "1"){
                connection.query("UPDATE cliente SET tentativas = 2 WHERE id = '"+msg.from+"'");
                connection.query("SELECT * FROM respostas WHERE nome = 'INFORMA-CPF-INVALIDO-2'",async function (err, resposta) {
                    wbot.sendMessage(msg.from,resposta[0].msg);
                })
              }
              // TERCEIRA TENTATIVA
              else if(cliente[0].tentativas === "2"){
                connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
                connection.query("SELECT * FROM respostas WHERE nome = 'INFORMA-CPF-INVALIDO-FIM'",async function (err, resposta) {
                    wbot.sendMessage(msg.from,resposta[0].msg);
                })
              }

        })}})
      }
      if (msg.from){
        const now = new Date();
          
        let diaSemana = now.getDay();
        var horaAtual = now.getHours(); 
        var minutoAtual = ("0" + (now.getMinutes() + 1)).substr(-2);
        var HoraAtual = horaAtual.toString() + minutoAtual.toString() 
        var HoraInicioSemana = '900'; // DEFINE O HORARIO DE ATENDIMENTO 
        var HoraInicioSabado = '900'; // DEFINE O HORARIO DE ATENDIMENTO 
        var HoraFimSemana = '1800';  // DEFINE O HORARIO DE ATENDIMENTO
        var HoraFimSabado = '1800';  // DEFINE O HORARIO DE ATENDIMENTO

        connection.query("SELECT * FROM cliente WHERE id = '"+msg.from+"'",async function (err, cliente) {
                // CADASTRANDO NO BD wppbot
            if(cliente[0] === undefined){
                connection.query("SELECT * FROM respostas WHERE nome = 'INICIO'",async function (err, resposta) {
                    console.log("NAO CADASTRADO");
                    connection.query("INSERT INTO cliente (id) VALUES('"+msg.from+"')");
                    connection.query("SELECT * FROM respostas WHERE nome = 'INICIO'",async function (err, resposta) {
                        const fileUrl = resposta[0].img;
                        const media = await MessageMedia.fromUrl(fileUrl);
                        await wbot.sendMessage(msg.from, media, {caption: "Olá, *" + msg._data.notifyName + "*\n" + resposta[0].msg});
                    });
                });}


// ######################## CHECANDO HORARIO DE ATENDIMENTO COMERCIAL ######################
else if(cliente[0].categoria === '3' && msg.body === "3"){
    if(diaSemana === 0){
        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO'",async function (err, resposta) {
            wbot.sendMessage(msg.from,resposta[0].msg);
            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
        })}

    else if(diaSemana === 6 && HoraAtual < HoraInicioSabado && HoraAtual >= HoraFimSabado){
        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO'",async function (err, resposta) {
            wbot.sendMessage(msg.from,resposta[0].msg);
            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
        })}

    else if(HoraAtual < HoraInicioSemana && HoraAtual >= HoraFimSemana){
        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO'",async function (err, resposta) {
            wbot.sendMessage(msg.from,resposta[0].msg);
            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
        })}

    else{
        var num = msg.from.replace(/\D/g, '');
        connection.query("SELECT * FROM Contacts WHERE number = '"+num+"'",async function (err, numero) {
            connection.query("SELECT * FROM respostas WHERE nome = 'TRANSFERINDO'",async function (err, resposta) {
                var contatoId = numero[0].id;
                connection.query("SELECT * from Tickets WHERE contactId = '"+contatoId+"' ORDER BY id DESC LIMIT 1",async function (err, ticket) {
                    connection.query("UPDATE cliente SET categoria = '0' WHERE id = '"+msg.from+"'");
                    connection.query("UPDATE Tickets SET queueId = '1', status = 'pending' WHERE id = '"+ticket[0].id+"'");                        
                    wbot.sendMessage(msg.from,"*_- Comercial -_*\n\n" + resposta[0].msg);
                    console.log("DENTRO ATÉ O ZÔVO");
                });
            });
        });
    }                        
}
// ##########################################################################################################################

// ######################## CHECANDO HORARIO DE ATENDIMENTO FINANCEIRO ######################
else if(cliente[0].categoria === '3' && msg.body === "4"){
    if(diaSemana === 0){
        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO'",async function (err, resposta) {
            wbot.sendMessage(msg.from,resposta[0].msg);
            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
        })}

    else if(diaSemana === 6 && HoraAtual < HoraInicioSabado && HoraAtual >= HoraFimSabado){
        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO'",async function (err, resposta) {
            wbot.sendMessage(msg.from,resposta[0].msg);
            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
        })}

    else if(HoraAtual < HoraInicioSemana && HoraAtual >= HoraFimSemana){
        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO'",async function (err, resposta) {
            wbot.sendMessage(msg.from,resposta[0].msg);
            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
        })}

    else{
        var num = msg.from.replace(/\D/g, '');
        connection.query("SELECT * FROM Contacts WHERE number = '"+num+"'",async function (err, numero) {
            connection.query("SELECT * FROM respostas WHERE nome = 'TRANSFERINDO'",async function (err, resposta) {
                var contatoId = numero[0].id;
                connection.query("SELECT * from Tickets WHERE contactId = '"+contatoId+"' ORDER BY id DESC LIMIT 1",async function (err, ticket) {
                    connection.query("UPDATE cliente SET categoria = '0' WHERE id = '"+msg.from+"'");
                    connection.query("UPDATE Tickets SET queueId = '2', status = 'pending' WHERE id = '"+ticket[0].id+"'");                        
                    wbot.sendMessage(msg.from,"*_- Financeiro -_*\n\n" + resposta[0].msg);
                    console.log("DENTRO ATÉ O ZÔVO");
                });
            });
        });
    }                        
}
// ##########################################################################################################################

// ######################## CHECANDO HORARIO DE ATENDIMENTO SUPORTE ######################
else if(cliente[0].categoria === '3' && msg.body === "5"){
    if(diaSemana === 0){
        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO'",async function (err, resposta) {
            wbot.sendMessage(msg.from,resposta[0].msg);
            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
        })}

    else if(diaSemana === 6 && HoraAtual < HoraInicioSabado && HoraAtual >= HoraFimSabado){
        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO'",async function (err, resposta) {
            wbot.sendMessage(msg.from,resposta[0].msg);
            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
        })}

    else if(HoraAtual < HoraInicioSemana && HoraAtual >= HoraFimSemana){
        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO'",async function (err, resposta) {
            wbot.sendMessage(msg.from,resposta[0].msg);
            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
        })}

    else{
        var num = msg.from.replace(/\D/g, '');
        connection.query("SELECT * FROM Contacts WHERE number = '"+num+"'",async function (err, numero) {
            connection.query("SELECT * FROM respostas WHERE nome = 'TRANSFERINDO'",async function (err, resposta) {
                var contatoId = numero[0].id;
                connection.query("SELECT * from Tickets WHERE contactId = '"+contatoId+"' ORDER BY id DESC LIMIT 1",async function (err, ticket) {
                    connection.query("UPDATE cliente SET categoria = '0' WHERE id = '"+msg.from+"'");
                    connection.query("UPDATE Tickets SET queueId = '3', status = 'pending' WHERE id = '"+ticket[0].id+"'");                        
                    wbot.sendMessage(msg.from,"*_- Suporte -_*\n\n" + resposta[0].msg);
                    console.log("DENTRO ATÉ O ZÔVO");
                });
            });
        });
    }                        
}
// ##########################################################################################################################

// ######################## CHECANDO HORARIO DE ATENDIMENTO COMERCIAL ######################
else if(cliente[0].categoria === '4' && msg.body === "3"){
    if(diaSemana === 0){
        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO'",async function (err, resposta) {
            wbot.sendMessage(msg.from,resposta[0].msg);
            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
        })}

    else if(diaSemana === 6 && HoraAtual < HoraInicioSabado && HoraAtual >= HoraFimSabado){
        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO'",async function (err, resposta) {
            wbot.sendMessage(msg.from,resposta[0].msg);
            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
        })}

    else if(HoraAtual < HoraInicioSemana && HoraAtual >= HoraFimSemana){
        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO'",async function (err, resposta) {
            wbot.sendMessage(msg.from,resposta[0].msg);
            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
        })}

    else{
        var num = msg.from.replace(/\D/g, '');
        connection.query("SELECT * FROM Contacts WHERE number = '"+num+"'",async function (err, numero) {
            connection.query("SELECT * FROM respostas WHERE nome = 'TRANSFERINDO'",async function (err, resposta) {
                var contatoId = numero[0].id;
                connection.query("SELECT * from Tickets WHERE contactId = '"+contatoId+"' ORDER BY id DESC LIMIT 1",async function (err, ticket) {
                    connection.query("UPDATE cliente SET categoria = '0' WHERE id = '"+msg.from+"'");
                    connection.query("UPDATE Tickets SET queueId = '1', status = 'pending' WHERE id = '"+ticket[0].id+"'");                        
                    wbot.sendMessage(msg.from,"*_- Comercial -_*\n\n" + resposta[0].msg);
                    console.log("DENTRO ATÉ O ZÔVO");
                });
            });
        });
    }                        
}
// ##########################################################################################################################

// ######################## CHECANDO HORARIO DE ATENDIMENTO FINANCEIRO ######################
else if(cliente[0].categoria === '4' && msg.body === "4"){
    if(diaSemana === 0){
        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO'",async function (err, resposta) {
            wbot.sendMessage(msg.from,resposta[0].msg);
            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
        })}

    else if(diaSemana === 6 && HoraAtual < HoraInicioSabado && HoraAtual >= HoraFimSabado){
        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO'",async function (err, resposta) {
            wbot.sendMessage(msg.from,resposta[0].msg);
            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
        })}

    else if(HoraAtual < HoraInicioSemana && HoraAtual >= HoraFimSemana){
        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO'",async function (err, resposta) {
            wbot.sendMessage(msg.from,resposta[0].msg);
            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
        })}

    else{
        var num = msg.from.replace(/\D/g, '');
        connection.query("SELECT * FROM Contacts WHERE number = '"+num+"'",async function (err, numero) {
            connection.query("SELECT * FROM respostas WHERE nome = 'TRANSFERINDO'",async function (err, resposta) {
                var contatoId = numero[0].id;
                connection.query("SELECT * from Tickets WHERE contactId = '"+contatoId+"' ORDER BY id DESC LIMIT 1",async function (err, ticket) {
                    connection.query("UPDATE cliente SET categoria = '0' WHERE id = '"+msg.from+"'");
                    connection.query("UPDATE Tickets SET queueId = '2', status = 'pending' WHERE id = '"+ticket[0].id+"'");                        
                    wbot.sendMessage(msg.from,"*_- Finaceiro -_*\n\n" + resposta[0].msg);
                    console.log("DENTRO ATÉ O ZÔVO");
                });
            });
        });
    }                        
}
// ##########################################################################################################################

// ######################## CHECANDO HORARIO DE ATENDIMENTO SUPORTE ######################
else if(cliente[0].categoria === '4' && msg.body === "5"){
    if(diaSemana === 0){
        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO'",async function (err, resposta) {
            wbot.sendMessage(msg.from,resposta[0].msg);
            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
        })}

    else if(diaSemana === 6 && HoraAtual < HoraInicioSabado && HoraAtual >= HoraFimSabado){
        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO'",async function (err, resposta) {
            wbot.sendMessage(msg.from,resposta[0].msg);
            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
        })}

    else if(HoraAtual < HoraInicioSemana && HoraAtual >= HoraFimSemana){
        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO'",async function (err, resposta) {
            wbot.sendMessage(msg.from,resposta[0].msg);
            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
        })}

    else{
        var num = msg.from.replace(/\D/g, '');
        connection.query("SELECT * FROM Contacts WHERE number = '"+num+"'",async function (err, numero) {
            connection.query("SELECT * FROM respostas WHERE nome = 'TRANSFERINDO'",async function (err, resposta) {
                var contatoId = numero[0].id;
                connection.query("SELECT * from Tickets WHERE contactId = '"+contatoId+"' ORDER BY id DESC LIMIT 1",async function (err, ticket) {
                    connection.query("UPDATE cliente SET categoria = '0' WHERE id = '"+msg.from+"'");
                    connection.query("UPDATE Tickets SET queueId = '3', status = 'pending' WHERE id = '"+ticket[0].id+"'");                        
                    await sleep(2000)
                    wbot.sendMessage(msg.from,"*_- Suporte -_*\n\n" + resposta[0].msg);
                    console.log("DENTRO ATÉ O ZÔVO");
                });
            });
        });
    }                        
}
// ##########################################################################################################################

// ################################ DESBLOQUEIO CONFIANÇA ######################################
                else if(cliente[0].categoria === '4' && msg.body === "2"){
                    PromPag(url,token,cliente[0].cpfcnpj);

                }
/// ############################### 2VIA DE FATURA ##############################################
                else if(cliente[0].categoria === '3' && msg.body === "1"){
                    if(cliente[0].ultimaFat === 'undefined'){
                        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-FATURA'",async function (err, resposta) {
                            wbot.sendMessage(msg.from,resposta[0].msg);
                        })
                    }
                    else{
                        connection.query("SELECT * FROM respostas WHERE nome = 'COM-FATURA'",async function (err, resposta) {
                            connection.query("SELECT * FROM respostas WHERE nome = 'FINALIZAR'",async function (err, respostas) {
                                connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
                            wbot.sendMessage(msg.from,resposta[0].msg + "\n\n*" + cliente[0].ultimaFat + "*\n\n" + respostas[0].msg);
                        })})                        
                    }
                }

                else if(cliente[0].categoria === '4' && msg.body === "1"){
                    if(cliente[0].ultimaFat){
                        connection.query("SELECT * FROM respostas WHERE nome = 'COM-FATURA'",async function (err, resposta) {
                            connection.query("SELECT * FROM respostas WHERE nome = 'FINALIZAR'",async function (err, respostas) {
                                connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
                            wbot.sendMessage(msg.from,resposta[0].msg + "\n\n*" + cliente[0].ultimaFat + "*\n\n" + respostas[0].msg);
                        })})                        
                    }
                    else{
                        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-FATURA'",async function (err, resposta) {
                            wbot.sendMessage(msg.from,resposta[0].msg);
                        })
                    }
                }

// ################################################################################################################

                







// ################################## E FINALIZAR ATENDIMENTO OP 0 ###############################
                else if(cliente[0].categoria === '3' && msg.body === "0"){
                    connection.query("SELECT * FROM respostas WHERE nome = 'FINALIZAR'",async function (err, resposta) {
                        connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
                        wbot.sendMessage(msg.from,resposta[0].msg);
                    })
            }
// ################################## SSEM RESPOSTA ###############################
                else if(cliente[0].categoria === '3'){
                    connection.query("SELECT * FROM cliente WHERE id = '"+msg.from+"'",async function (err, cliente) {
                        wbot.sendMessage(msg.from,"*_CENTRAL DO ASSINANTE_*\n====================\n*" + cliente[0].nome + "*\nStatus: " + cliente[0].contratoStatusDisplay + "\n\n1️⃣ *2Via Fatura*\n\n3️⃣ *Falar com Comercial*\n4️⃣ *Falar com Financeiro*\n5️⃣ *Falar com Suporte*\n\n_*Acesse Central:*_\n*https://turbonet.rbfull.com.br/central/*\n_(basta informa seu *CPF*)_\n\n0️⃣ *Encerrar Atendimento*");
                    })
            }


// ################################## E FINALIZAR ATENDIMENTO OP 0 ###############################
                else if(cliente[0].categoria === '4' && msg.body === "0"){
                    connection.query("SELECT * FROM respostas WHERE nome = 'FINALIZAR'",async function (err, resposta) {
                        connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
                        wbot.sendMessage(msg.from,resposta[0].msg);
                    })
            }
// ################################## SSEM RESPOSTA ###############################
                else if(cliente[0].categoria === '4'){
                    connection.query("SELECT * FROM cliente WHERE id = '"+msg.from+"'",async function (err, cliente) {
                        wbot.sendMessage(msg.from,"*_CENTRAL DO ASSINANTE_*\n====================\n*" + cliente[0].nome + "*\nStatus: " + cliente[0].contratoStatusDisplay + "\n\n1️⃣ *2Via Fatura*\n2️⃣ *Desb. Confiança*\n3️⃣ *Falar com Comercial*\n4️⃣ *Falar com Financeiro*\n5️⃣ *Falar com Suporte*\n\n_*Acesse Central:*_\n*https://turbonet.rbfull.com.br/central/*\n_(basta informa seu *CPF*)_\n\n0️⃣ *Encerrar Atendimento*");
                    })
            }

// ################################## E CLIENTE OP 1 ###############################
                else if(cliente[0].categoria === '1' && msg.body === "1"){
                    connection.query("SELECT * FROM respostas WHERE nome = 'INFORMA-CPF'",async function (err, resposta) {
                        connection.query("UPDATE cliente SET categoria = 2 WHERE id = '"+msg.from+"'");
                        wbot.sendMessage(msg.from,resposta[0].msg);
                    })
            }


// ################################## DIGITA CPF ###############################
            else if(cliente[0].categoria === '2'){
                SegundaVia(url,token,msg.body, msg.from);
        }

// ################################# NAO E CLIENTE OP 2 ###############################
// ######################## CHECANDO HORARIO DE ATENDIMENTO ######################
                else if(cliente[0].categoria === '1' && msg.body === "2"){
                    if(diaSemana === 0){
                        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO-COM'",async function (err, resposta) {
                            wbot.sendMessage(msg.from,resposta[0].msg);
                            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
                        })}
    
                    else if(diaSemana === 6 && HoraAtual < HoraInicioSabado && HoraAtual >= HoraFimSabado){
                        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO-COM'",async function (err, resposta) {
                            wbot.sendMessage(msg.from,resposta[0].msg);
                            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
                        })}
    
                    else if(HoraAtual < HoraInicioSemana && HoraAtual >= HoraFimSemana){
                        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO-COM'",async function (err, resposta) {
                            wbot.sendMessage(msg.from,resposta[0].msg);
                            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
                        })}
    
                    else{
                        var num = msg.from.replace(/\D/g, '');
                        connection.query("SELECT * FROM Contacts WHERE number = '"+num+"'",async function (err, numero) {
                            connection.query("SELECT * FROM respostas WHERE nome = 'TRANSFERINDO'",async function (err, resposta) {
                                var contatoId = numero[0].id;
                                connection.query("SELECT * from Tickets WHERE contactId = '"+contatoId+"' ORDER BY id DESC LIMIT 1",async function (err, ticket) {
                                    connection.query("UPDATE cliente SET categoria = '0' WHERE id = '"+msg.from+"'");
                                    connection.query("UPDATE Tickets SET queueId = '1', status = 'pending' WHERE id = '"+ticket[0].id+"'");                        
                                    wbot.sendMessage(msg.from,"*_- Comercial -_*\n\n" + resposta[0].msg);
                                    console.log("DENTRO ATÉ O ZÔVO");
                                });
                            });
                        });
                    }                        
                }
                   
// ################################# FIM NAO E CLIENTE ###############################

// ################################# SOU TECNICO ###############################
// ######################## CHECANDO HORARIO DE ATENDIMENTO ######################
else if(cliente[0].categoria === '1' && msg.body === "3"){
    if(diaSemana === 0){
        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO-COM'",async function (err, resposta) {
            wbot.sendMessage(msg.from,resposta[0].msg);
            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
        })}

    else if(diaSemana === 6 && HoraAtual < HoraInicioSabado && HoraAtual >= HoraFimSabado){
        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO-COM'",async function (err, resposta) {
            wbot.sendMessage(msg.from,resposta[0].msg);
            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
        })}

    else if(HoraAtual < HoraInicioSemana && HoraAtual >= HoraFimSemana){
        connection.query("SELECT * FROM respostas WHERE nome = 'SEM-ATENDIMENTO-COM'",async function (err, resposta) {
            wbot.sendMessage(msg.from,resposta[0].msg);
            connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
        })}

    else{
        connection.query("UPDATE cliente SET categoria = '9' WHERE id = '"+msg.from+"'");
        wbot.sendMessage(msg.from,"⚠️ _*AUTENTICAÇÃO*_ ⚠️\n\n_Por favor,_\nDigite sua *Senha* para continar");
    }                        
}
else if(cliente[0].categoria === '9'){
    if(msg.body === senha){
        var num = msg.from.replace(/\D/g, '');
        connection.query("SELECT * FROM Contacts WHERE number = '"+num+"'",async function (err, numero) {
            connection.query("SELECT * FROM respostas WHERE nome = 'TRANSFERINDO'",async function (err, resposta) {
                var contatoId = numero[0].id;
                connection.query("SELECT * from Tickets WHERE contactId = '"+contatoId+"' ORDER BY id DESC LIMIT 1",async function (err, ticket) {
                    connection.query("UPDATE cliente SET categoria = '0' WHERE id = '"+msg.from+"'");
                    connection.query("UPDATE Tickets SET queueId = '3', status = 'pending' WHERE id = '"+ticket[0].id+"'");                        
                    wbot.sendMessage(msg.from,"*_- Suporte -_*\n\n" + resposta[0].msg);
                    console.log("DENTRO ATÉ O ZÔVO");
                });
            });
        });
    }
    else{
        wbot.sendMessage(msg.from,"❌ _*Senha Inválida*_ ❌\n\n_Atendimento finalizado..._\n_Até logo_ 😊");
        connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'")
    }

}
   
// ################################# FIM SOU TECNICO ###############################





                else if(cliente[0].categoria === '1'){
                    //MENSAGEM DE INICIO SEM IMAGEM
                    connection.query("SELECT * FROM respostas WHERE nome = 'INICIO-S-IMG'",async function (err, resposta) {
                        const fileUrl = resposta[0].img;
                        await wbot.sendMessage(msg.from,resposta[0].msg);
//                        SegundaVia(url,token,msg.body)
                    });
                }
                else if(cliente[0].categoria === '0'){
                    var num = msg.from.replace(/\D/g, '');
                    connection.query("SELECT * FROM Contacts WHERE number = '"+num+"'",async function (err, numero) {
                        var contatoId = numero[0].id;
                        connection.query("SELECT * from Tickets WHERE contactId = '"+contatoId+"' ORDER BY id DESC LIMIT 1",async function (err, ticket) {

                            if(ticket[0].status === 'closed'){
                                connection.query("DELETE FROM cliente WHERE id = '"+msg.from+"'");
                                connection.query("SELECT * FROM respostas WHERE nome = 'INICIO'",async function (err, resposta) {
                                    console.log("NAO CADASTRADO");
                                    connection.query("INSERT INTO cliente (id) VALUES('"+msg.from+"')");
                                    connection.query("SELECT * FROM respostas WHERE nome = 'INICIO'",async function (err, resposta) {
                                        const fileUrl = resposta[0].img;
                                        const media = await MessageMedia.fromUrl(fileUrl);
                                        await wbot.sendMessage(msg.from, media, {caption: "Olá, *" + msg._data.notifyName + "*\n" + resposta[0].msg});
                                    });
                                });
                            }

                        });});

                }
            });
        }
        else {
            
        }
    });
// ENVIO DE MENSAGEM DE MULTIMIDIA
//                            const fileUrl = "https://dctsistemas.com/TURBONETPNG.png";
//                            const media = await MessageMedia.fromUrl(fileUrl);
//                            await wbot.sendMessage(msg.from, media, {caption: ""});

// ENVIO DE MENSAGEM DE TEXTO
//                            wbot.sendMessage(msg.from, msg.type + "\n" + msg.to + "\n" + msg.body);

// ENVIO DE MENSAGEM DE RESPOSTA
//                            msg.reply(msg.type + "\n" + msg.to + "\n" + msg.body);
//                            console.log(msg);
                io.emit("whatsappSession", {
                    action: "update",
                    session: whatsapp
                });
                const sessionIndex = sessions.findIndex(s => s.id === whatsapp.id);
                if (sessionIndex === -1) {
                    wbot.id = whatsapp.id;
                    sessions.push(wbot);
                }
                wbot.sendPresenceAvailable();
                yield syncUnreadMessages(wbot);
                resolve(wbot);
            }));
        }
        catch (err) {
            logger_1.logger.error(err);
        }
    });
});
exports.getWbot = (whatsappId) => {
    const sessionIndex = sessions.findIndex(s => s.id === whatsappId);
    if (sessionIndex === -1) {
        throw new AppError_1.default("ERR_WAPP_NOT_INITIALIZED");
    }
    return sessions[sessionIndex];
};
exports.removeWbot = (whatsappId) => {
    try {
        const sessionIndex = sessions.findIndex(s => s.id === whatsappId);
        if (sessionIndex !== -1) {
            sessions[sessionIndex].destroy();
            sessions.splice(sessionIndex, 1);
        }
    }
    catch (err) {
        logger_1.logger.error(err);
    }
};


[-]EOF

EOF
  sleep 2
}

#######################################
# updates frontend code
# Arguments:
#   None
#######################################
backend_update() {
  print_banner
  printf "${WHITE} 💻 Atualizando o backend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${empresa_atualizar}
  pm2 stop ${empresa_atualizar}-backend
  git pull
  cd /home/deploy/${empresa_atualizar}/backend
  npm install
  npm update -f
  npm install @types/fs-extra
  rm -rf dist 
  npm run build
  npx sequelize db:migrate
  npx sequelize db:seed
  pm2 start ${empresa_atualizar}-backend
  pm2 save 
EOF

  sleep 2
}

#######################################
# runs db migrate
# Arguments:
#   None
#######################################
backend_db_migrate() {
  print_banner
  printf "${WHITE} 💻 Executando db:migrate...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/backend
  npx sequelize db:migrate
EOF

  sleep 2
}

#######################################
# runs db seed
# Arguments:
#   None
#######################################
backend_db_seed() {
  print_banner
  printf "${WHITE} 💻 Executando db:seed...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/backend
  npx sequelize db:seed:all
EOF

  sleep 2
}

#######################################
# starts backend using pm2 in 
# production mode.
# Arguments:
#   None
#######################################
backend_start_pm2() {
  print_banner
  printf "${WHITE} 💻 Iniciando pm2 (backend)...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/backend
  pm2 start dist/server.js --name ${instancia_add}-backend
EOF

  sleep 2
}

#######################################
# updates frontend code
# Arguments:
#   None
#######################################
backend_nginx_setup() {
  print_banner
  printf "${WHITE} 💻 Configurando nginx (backend)...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  backend_hostname=$(echo "${backend_url/https:\/\/}")

sudo su - root << EOF
cat > /etc/nginx/sites-available/${instancia_add}-backend << 'END'
server {
  server_name $backend_hostname;
  location / {
    proxy_pass http://127.0.0.1:${backend_port};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_cache_bypass \$http_upgrade;
  }
}
END
ln -s /etc/nginx/sites-available/${instancia_add}-backend /etc/nginx/sites-enabled
EOF

  sleep 2
}
