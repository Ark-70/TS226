clear
clc

%% Parametres
% -------------------------------------------------------------------------

R = 1; % Rendement de la communication (R=1 au debut pour BPSK)
% R = 1/2; % Rendement quand code convolutif treillis ouvert


constlen1 = 2; % les bits de terminaison du treillis = longueur de contrainte-1
% En vrai c'est le nombre de cases mémoire + 1 pour l'entrée
treillisStruct1 = poly2trellis(constlen1, [2 3]);

constlen2 = 3;
treillisStruct2 = poly2trellis(constlen2, [7 5]);
constlen3 = 4;
treillisStruct3 = poly2trellis(constlen3, [13 15]);
constlen4 = 7;
treillisStruct4 = poly2trellis(constlen4, [133 171]);

constlen = constlen4;
treillisStruct = treillisStruct4;

d_spec = distspec(treillisStruct);
d_min_hamming = d_spec.dfree


pqt_par_trame = 100; % Nombre de paquets par trame
bit_par_pqt   = 330;% Nombre de bit par paquet
K = pqt_par_trame*bit_par_pqt; % Nombre de bits de message par trame
% K = 10
m = constlen - 1 % bits (avant codage) de fermeture == nombre de cases mémoire
R = K/(2*(m + K))

N = K/R; % Nombre de bits cod�s par trame (cod�e) nb bit besoin pour une trame entière après codage.

Mmod = 2; % Modulation BPSK <=> M = 2 symboles

% R =
% code convolutif / code binaire en bloc /


phi0 = 0; % Offset de phase our la BPSK

EbN0dB_min  = -2; % Minimum de EbN0
EbN0dB_max  = 10; % Maximum de EbN0
EbN0dB_step = 1;% Pas de EbN0

nbr_erreur  = 100;  % Nombre d'erreurs � observer avant de calculer un BER
nbr_bit_max = 100e6;% Nombre de bits max � simuler
ber_min     = 3e-5; % BER min

EbN0dB = EbN0dB_min:EbN0dB_step:EbN0dB_max;     % Points de EbN0 en dB � simuler
EbN0   = 10.^(EbN0dB/10);% Points de EbN0 � simuler
EsN0   = R*log2(Mmod)*EbN0; % Points de EsN0
EsN0dB = 10*log10(EsN0); % Points de EsN0 en dB � simuler


% -------------------------------------------------------------------------

%% Construction de l'encodeur convolutif
encod_conv = comm.ConvolutionalEncoder(...
    'TrellisStructure', treillisStruct, ...
    'TerminationMethod', 'Truncated');

%% Construction du modulateur
mod_psk = comm.PSKModulator(...
    'ModulationOrder', Mmod, ... % BPSK
    'PhaseOffset'    , phi0, ...
    'SymbolMapping'  , 'Gray',...
    'BitInput'       , true);

%% Construction du demodulateur
demod_psk = comm.PSKDemodulator(...
    'ModulationOrder', Mmod      , ...
    'PhaseOffset'    , phi0   , ...
    'SymbolMapping'  , 'Gray' , ...
    'BitOutput'      , true   , ...
    'DecisionMethod' , 'Log-likelihood ratio');

%% Construction du décodeur Viterbi
decod_viter = comm.ViterbiDecoder(...
    'TrellisStructure'  , treillisStruct , ...
    'TerminationMethod' , 'Truncated'    , ...
    'TracebackDepth'    , constlen*5+1   , ...
    'InputFormat'       , 'Unquantized'   );



%% Construction du canal AWGN
awgn_channel = comm.AWGNChannel(...
    'NoiseMethod', 'Signal to noise ratio (Es/No)',...
    'EsNo',EsN0dB(1),...
    'SignalPower',1);

%% Construction de l'objet �valuant le TEB
stat_erreur = comm.ErrorRate(); % Calcul du nombre d'erreur et du BER

%% Initialisation des vecteurs de r�sultats
ber = zeros(1,length(EbN0dB));
Pe = qfunc(sqrt(2*EbN0));

%% Pr�paration de l'affichage
figure(1)
h_ber = semilogy(EbN0dB,ber,'XDataSource','EbN0dB', 'YDataSource','ber');
hold all
ylim([1e-6 1])
grid on
xlabel('$\frac{E_b}{N_0}$ en dB','Interpreter', 'latex', 'FontSize',14)
ylabel('TEB','Interpreter', 'latex', 'FontSize',14)

%% Pr�paration de l'affichage en console
msg_format = '|   %7.2f  |   %9d   |  %9d | %2.2e |  %8.2f kO/s |   %8.2f kO/s |   %8.2f s |\n';

fprintf(      '|------------|---------------|------------|----------|----------------|-----------------|--------------|\n')
msg_header =  '|  Eb/N0 dB  |    Bit nbr    |  Bit err   |   TEB    |    Debit Tx    |     Debit Rx    | Tps restant  |\n';
fprintf(msg_header);
fprintf(      '|------------|---------------|------------|----------|----------------|-----------------|--------------|\n')


%% Simulation
for i_snr = 1:length(EbN0dB)
    reverseStr = ''; % Pour affichage en console
    awgn_channel.EsNo = EsN0dB(i_snr);% Mise a jour du EbN0 pour le canal

    stat_erreur.reset; % reset du compteur d'erreur
    err_stat    = [0 0 0]; % vecteur r�sultat de stat_erreur

    demod_psk.Variance = awgn_channel.Variance;

    n_frame = 0;
    T_rx = 0;
    T_tx = 0;
    general_tic = tic;
    while (err_stat(2) < nbr_erreur && err_stat(3) < nbr_bit_max)
        n_frame = n_frame + 1;

        %% Emetteur
        tx_tic    = tic;                      % Mesure du d�bit d'encodage
        msg       = randi([0,1],K,1);         % G�n�ration du message al�atoire
        msg_encod = step(encod_conv,  msg);   % Encodage convolutif
        x         = step(mod_psk,  msg_encod);% Modulation QPSK
        T_tx      = T_tx+toc(tx_tic);         % Mesure du d�bit d'encodage

        %% Canal
        y     = step(awgn_channel, x); % Ajout d'un bruit gaussien
%         y = x;

        %% Recepteur
        rx_tic  = tic;                  % Mesure du d�bit de d�codage
        Lc      = step(demod_psk, y);   % D�modulation (retourne des LLRs)
        rec_msg = step(decod_viter, Lc); % Décodage par Viterbi
        rec_msg = rec_msg(1:K);
        %rec_msg = double(rec_msg(1:K) < 0); % D�cision
        T_rx    = T_rx + toc(rx_tic);  % Mesure du d�bit de d�codage

        err_stat   = step(stat_erreur, msg, rec_msg); % Comptage des erreurs binaires

        %% Affichage du r�sultat
        if mod(n_frame,100) == 1
            display_str = sprintf(msg_format,...
                EbN0dB(i_snr),         ... % EbN0 en dB
                err_stat(3),           ... % Nombre de bits envoy�s
                err_stat(2),           ... % Nombre d'erreurs observ�es
                err_stat(1),           ... % BER
                err_stat(3)/8/T_tx/1e3,... % D�bit d'encodage
                err_stat(3)/8/T_rx/1e3,... % D�bit de d�codage
                toc(general_tic)*(nbr_erreur - min(err_stat(2),nbr_erreur))/nbr_erreur); % Temps restant
            fprintf(reverseStr);
            msg_sz =  fprintf(display_str);
            reverseStr = repmat(sprintf('\b'), 1, msg_sz);
        end

    end

    display_str = sprintf(msg_format,EbN0dB(i_snr), err_stat(3), err_stat(2), err_stat(1), err_stat(3)/8/T_tx/1e3, err_stat(3)/8/T_rx/1e3, toc(general_tic)*(100 - min(err_stat(2),100))/100);
    fprintf(reverseStr);
    msg_sz =  fprintf(display_str);
    reverseStr = repmat(sprintf('\b'), 1, msg_sz);

    ber(i_snr) = err_stat(1);
    refreshdata(h_ber);
    drawnow limitrate

    if err_stat(1) < ber_min
        break
    end

end
fprintf('|------------|---------------|------------|----------|----------------|-----------------|--------------|\n')

%%
figure(1)
semilogy(EbN0dB,ber);
hold all
xlim([0 10])
ylim([1e-6 1])
grid on
xlabel('$\frac{E_b}{N_0}$ en dB','Interpreter', 'latex', 'FontSize',14)
ylabel('TEB','Interpreter', 'latex', 'FontSize',14)
title('TEB pour chaque code');
legend('C(2,3)_8');

save('NC.mat','EbN0dB','ber')
