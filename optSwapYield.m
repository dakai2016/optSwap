function results = optSwapYield(model, opt)
% Adapted from RobustKnock.m
% By Zachary King 10/16/2012
%
% INPUTS
% model
% dhRxns
%
% OPTIONAL
% opt - struct with an of the following options:
%   targetRxn - chemical to produce
%   useCobraSolver - (unfinished) 1 use any cobra solver; 0 use tomlab cplex solver
%   maxW - maximal value of dual variables (higher number will be more
%          accurate but takes more calculation time)
%   biomassRxn
%   swapNum - number of swaps
%   dhRxns - dehydrogenase reaction list
%   minBiomass
%
% OUTPUTS
% results


    if nargin < 1, error('Not enough arguments'); end

    % set default parameters
    if ~exist('opt','var')
        opt = struct();
    end
    if ~isfield(opt,'targetRxn'), opt.targetRxn = 'EX_for(e)'; end
    if ~isfield(opt,'knockoutNum'), opt.knockoutNum = 3; end
    if ~isfield(opt,'knockType'), opt.knockType = 0; end
    if ~isfield(opt,'knockableRxns'), opt.knockableRxns = {}; end
    if ~isfield(opt,'notKnockableRxns'), opt.notKnockableRxns = {}; end
    if ~isfield(opt,'useCobraSolver'), opt.useCobraSolver = 0; end
    if ~isfield(opt,'maxW'),
        switch (opt.knockType)
          case 2, opt.maxW = 1e7;
          case 1, opt.maxW = 1e7;
          case 0, opt.maxW = 1000;
        end
    end
    if ~isfield(opt,'biomassRxn')
        opt.biomassRxn = model.rxns(model.c~=0);
    end
    if ~isfield(opt,'swapNum'), opt.swapNum = 0; end
    if ~isfield(opt,'dhRxns'), opt.dhRxns = {}; end
    if ~isfield(opt,'minBiomass'), opt.minBiomass = 0.0; end

    printLevel = 10;

    % Make dehydrogenases irreversible
    % TODO more general version where they can be reversible
    % model.lb(ismember(model.rxns, opt.dhRxns)) = 0;
    % model.rev(ismember(model.rxns, opt.dhRxns)) = 0;
    
    % swap all dh's
    [model, newNames, qsCoupling] = modelSwap(model, opt.dhRxns, true);
    model.lb(ismember(model.rxns, opt.biomassRxn)) = opt.minBiomass;
    
    chemicalInd = find(ismember(model.rxns, opt.targetRxn));
    if printLevel>=3, display(sprintf('chemical index %d', chemicalInd)); end

    %parameters
    findMaxWFlag=0;
    P=1;
    coupledFlag = 1;
    L = opt.swapNum;

    disp('preparing model')
    consModel = prepareOptSwapModel(model, chemicalInd, opt.biomassRxn);
    
    disp('createRobustOneWayFluxesModel')
    [model, qInd, qCoupledInd, sInd, sCoupledInd,...
     notYqsInd, notYqsCoupedInd, m, n, coupled] = ...
        createRobustOneWayFluxesModelYield(consModel, chemicalInd, coupledFlag, ...
                                      qsCoupling, opt.useCobraSolver);
    
    yInd = []; yCoupledInd = []; ySize = 0; yCoupledSize = 0;

    % sizes
    qSize = length(qInd); qCoupledSize = length(qCoupledInd);
    sSize = length(sInd); sCoupledSize = length(sCoupledInd);
    if (qSize ~= sSize)
        error('Dehydrogenases do not match swap reactions.');
    end
    if printLevel>=3
        display(sprintf('ySize %d, qSize %d, sSize %d',...
                        ySize, qSize, sSize));
        display(sprintf('yCoupledSize %d, qCoupledSize %d, sCoupledSize %d',...
                        yCoupledSize, qCoupledSize, sCoupledSize));
    end

    % don't sort combination indexes
    % yqsCoupledInd = [yCoupledInd; qCoupledInd; sCoupledInd];
    yqsInd = [yInd; qInd; sInd];

    % combined sizes
    yqsSize = ySize + qSize + sSize;
    yqsCoupledSize = yCoupledSize + qCoupledSize + sCoupledSize;

    %------------------------------------------------
    disp('setting up problem');
    % max C'v
    % s.t
    % [A,Ay] * [v;y] <= B

    I = eye(m);
    A=[
        model.S;
        -model.S;
        I(notYqsInd,:);
        I(notYqsCoupedInd,:);
        -I(notYqsInd,:);
        -I(notYqsCoupedInd,:);
        I([yInd; yCoupledInd; qInd; qCoupledInd; sInd; sCoupledInd;],:);
        -I([yInd; yCoupledInd; qInd; qCoupledInd; sInd; sCoupledInd;],:);
      ];

    [aSizeRow, vSize] = size(A);
    selYInd = zeros(m,1); selQInd = zeros(m,1); selSInd = zeros(m,1);
    selYInd(yInd) = 1; selQInd(qInd) = 1; selSInd(sInd) = 1;

    % Ay1, Aq1, As1
    Ay1=diag(selYInd);
    Ay1(coupled(:,2), :)=Ay1(coupled(:,1), :);
    Ay1=Ay1*diag(model.ub);

    Aq1=diag(selQInd);
    Aq1(coupled(:,2), :)=Aq1(coupled(:,1), :);
    Aq1=Aq1*diag(model.ub);

    As1=diag(selSInd);
    As1(coupled(:,2), :)=As1(coupled(:,1), :);
    As1=As1*diag(model.ub);

    for j=1:length(coupled)
        if (model.ub(coupled(j,1)) ~=0)
            Ay1(coupled(j,2), coupled(j,1)) = ...
                Ay1(coupled(j,2), coupled(j,1))  .*  ...
                (model.ub(coupled(j,2)) ./ model.ub(coupled(j,1)));
            Aq1(coupled(j,2), coupled(j,1)) = ...
                Aq1(coupled(j,2), coupled(j,1))  .*  ...
                (model.ub(coupled(j,2)) ./ model.ub(coupled(j,1)));
            As1(coupled(j,2), coupled(j,1)) = ...
                As1(coupled(j,2), coupled(j,1))  .*  ...
                (model.ub(coupled(j,2)) ./ model.ub(coupled(j,1)));
        end
    end

    % Ay2, Aq2, As2
    Ay2=diag(selYInd);
    Ay2(coupled(:,2), :)=Ay2(coupled(:,1), :);
    Ay2=Ay2*diag(model.lb);

    Aq2=diag(selQInd);
    Aq2(coupled(:,2), :)=Aq2(coupled(:,1), :);
    Aq2=Aq2*diag(model.lb);

    As2=diag(selSInd);
    As2(coupled(:,2), :)=As2(coupled(:,1), :);
    As2=As2*diag(model.lb);

    for j=1:length(coupled)
        if (model.lb(coupled(j,1)) ~=0)
            Ay2(coupled(j,2), coupled(j,1)) = ...
                Ay2(coupled(j,2), coupled(j,1))  .*  ...
                (model.lb(coupled(j,2)) ./ model.lb(coupled(j,1)));
            Aq2(coupled(j,2), coupled(j,1)) = ...
                Aq2(coupled(j,2), coupled(j,1))  .*  ...
                (model.lb(coupled(j,2)) ./ model.lb(coupled(j,1)));
            As2(coupled(j,2), coupled(j,1)) = ...
                As2(coupled(j,2), coupled(j,1))  .*  ...
                (model.lb(coupled(j,2)) ./ model.lb(coupled(j,1)));
        end
    end

    z1 = [find(Ay1); find(Aq1); find(As1)];
    z2 = [find(Ay2); find(Aq2); find(As2)];
    zSize = size([z1;z2],1);
    % TODO: where do we use z1, z2?
    if printLevel>=3, fprintf('zSize %d\n', zSize); end

    yqsCoupledSize = length(yCoupledInd) + length(qCoupledInd) + length(sCoupledInd);
    Ayqs = [
        zeros(2*n+2*(vSize-yqsSize-yqsCoupledSize),yqsSize);
        -Ay1(yInd,yqsInd);
        -Ay1(yCoupledInd,yqsInd);      % good!!
        -Aq1(qInd,yqsInd);
        -Aq1(qCoupledInd,yqsInd);
        -As1(sInd,yqsInd);
        -As1(sCoupledInd,yqsInd);
        Ay2(yInd,yqsInd);
        Ay2(yCoupledInd,yqsInd);
        Aq2(qInd,yqsInd);
        Aq2(qCoupledInd,yqsInd);
        As2(sInd,yqsInd);
        As2(sCoupledInd,yqsInd);
           ];  %flux boundary constraints

    sCoupledMatrix = zeros(qSize, qSize);
    qsCoupling_S = qsCoupling(:,2);
    for i = 1:qSize
        thisSIndex = qsCoupling_S(qsCoupling(:,1)==qInd(i));
        sCoupledMatrix(i,sInd==thisSIndex) = 1;
    end
    A = [A, Ayqs;
         % limit swap num
         zeros(1, vSize + ySize), -ones(1, qSize),  zeros(1, sSize);
         % swap constraints
         zeros(qSize, vSize + ySize), eye(qSize), sCoupledMatrix;
         zeros(qSize, vSize + ySize), -eye(qSize), -sCoupledMatrix;];
    
    %so: [A,Ayqs]x<=B;
    B = [
        zeros(2*n,1);
        model.ub(notYqsInd);
        model.ub(notYqsCoupedInd);
        -model.lb(notYqsInd);
        -model.lb(notYqsCoupedInd);
        zeros(2 * (yqsSize + yqsCoupledSize), 1); % knockout reactions with
                                                  %   corresponding qs vals
        L - qSize;                                % limit swap num
        ones(qSize, 1);                           % swap constraints
        -ones(qSize, 1);                          % swap constraints
        ];

    % Maximize chemicalInd
    C = [-model.C_chemical;
         zeros(yqsSize, 1);];
    
    intVars = (vSize + 1):(vSize + yqsSize);
    fprintf('size of intVars: %d\n', length(intVars));
    lb = [model.lb;
          zeros(yqsSize, 1)];
    ub = [model.ub;
          ones(yqsSize, 1)];
    
    useCobraSolver = opt.useCobraSolver;
    
    %solve milp
    %parameter for mip assign
    x_min = []; x_max = []; f_Low = -1E7; % f_Low <= f_optimal must hold
    f_opt = -141278;
    nProblem = 7; % Use the same problem number as in mip_prob.m
    fIP = []; % Do not use any prior knowledge
    xIP = []; % Do not use any prior knowledge
    setupFile = []; % Just define the Prob structure, not any permanent setup file
    x_opt = []; % The optimal integer solution is not known
    VarWeight = []; % No variable priorities, largest fractional part will be used
    KNAPSACK = 0; % First run without the knapsack heuristic


    %solving mip
    disp('mipAssign')
    if (useCobraSolver)
        MILPproblem.c = C;
        MILPproblem.osense = -1;
        MILPproblem.A = A;
        MILPproblem.b_L = [];
        MILPproblem.b_U = B;
        MILPproblem.b = B;
        MILPproblem.lb = lb; MILPproblem.ub = ub;
        MILPproblem.x0 = [];
        MILPproblem.vartype = char(ones(1,length(C)).*double('C'));
        MILPproblem.vartype(intVars) = 'I'; % assume no binary 'B'?
        MILPproblem.csense = [];

        [MILPproblem,solverParams] = setParams(MILPproblem, true);

        results = solveCobraMILP(MILPproblem,solverParams);

        % TODO: finish setting up this result analysis:
        YsNotRound=Result_tomRun.x_k(intVars);
        Ys=round(YsNotRound);
        knockedYindNotRound=find(1.-YsNotRound);
        knockedYindRound=find(1.-Ys);
        knockedVindRobustKnock=yInd(knockedYindRound);

        results.exitFlag = Result_tomRun.ExitFlag;
        results.organismObjectiveInd = model.organismObjectiveInd;
        results.chemicalInd = model.chemicalInd;
        results.chemical = -Result_tomRun.f_k;
        results.exitFlag = Result_tomRun.ExitFlag;
        results.ySize = ySize;
        results.ySum = sum(Result_tomRun.x_k(intVars));
        % results.yLowerBoundry = ySize-K;
        results.knockedYindRound = knockedYindRound;
        results.knockedYvalsRound = YsNotRound(knockedYindRound);
        results.y = Ys;
        results.knockedVind = knockedVindRobustKnock;

        results.solver = 'cobraSolver';

        % tomlabProblem = mipAssign(osense*c,A,b_L,b_U,lb,ub,x0,'CobraMILP',[],[],intVars);
        % varWeight = []
        % KNAPSACK
        % fIP = []
        % xIP = []
        % f_Low = -1E7
        % x_min = []
        % x_max = []
        % f_opt = -141278
        % x_opt = []

    else

        Prob_OptKnock2=mipAssign(C, A, [], B, lb, ub, [], 'part 3 MILP', ...
                                 setupFile, nProblem, ...
                                 intVars, VarWeight, KNAPSACK, fIP, xIP, ...
                                 f_Low, x_min, x_max, f_opt, x_opt);

        disp('setParams')
        Prob_OptKnock2 = setParams(Prob_OptKnock2);
        disp('tomRun')

        Result_tomRun = tomRun('cplex', Prob_OptKnock2, 2);

        save('raw results','Result_tomRun');

        results.raw = Result_tomRun;
        results.C = C;
        results.A = A;
        results.B = B;
        results.lb = lb;
        results.ub = ub;
        results.L = L;
        results.intVars = intVars;
        results.yInd = yInd;
        results.qInd = qInd;
        results.sInd = sInd;
        results.qCoupledInd = qCoupledInd;
        results.sCoupledInd = sCoupledInd;
        results.coupled = coupled;
        results.qsCoupling = qsCoupling;

        ySize = length(yInd); qSize = length(qInd); sSize = length(sInd);
        results.y = Result_tomRun.x_k(intVars(1:ySize));
        results.q = Result_tomRun.x_k(intVars(ySize+1:ySize+qSize));
        results.s = Result_tomRun.x_k(intVars(ySize+qSize+1:ySize+qSize+sSize));

        results.exitFlag = Result_tomRun.ExitFlag;
        results.inform = Result_tomRun.Inform;
        results.organismObjectiveInd = model.organismObjectiveInd;
        results.chemicalInd = model.chemicalInd;
        results.chemical = -Result_tomRun.f_k;
        results.f_k = Result_tomRun.f_k;
        results.knockoutRxns = model.rxns(yInd(results.y==0));
        results.knockoutDhs = model.rxns(qInd(results.q==0));
        results.knockoutSwaps = model.rxns(sInd(results.s==0));
        results.model = model;

        results.solver = 'tomlab_cplex';
    end


end



function consModel=prepareOptSwapModel(model, chemicalInd, biomassRxn)

%lets start!

    consModel=model;
    [metNum, rxnNum] = size(consModel.S);
    consModel.row_lb=zeros(metNum,1);
    consModel.row_ub=zeros(metNum,1);

    % setup chemical objective
    consModel.C_chemical=zeros(rxnNum,1);
    consModel.C_chemical(chemicalInd)=1;

    % add chemical index to model
    consModel.chemicalInd = chemicalInd;

    % setup biomass objective
    biomassInd = find(ismember(model.rxns, biomassRxn));
    if isempty(biomassInd)
        error('biomass reaction not found in model');
        return;
    end
    consModel.organismObjectiveInd = biomassInd;
    consModel.organismObjective = zeros(rxnNum,1);
    consModel.organismObjective(biomassInd) = 1;

    %remove small  reactions
    sel1 = (consModel.S>-(10^-3) & consModel.S<0);
    sel2 = (consModel.S<(10^-3) & consModel.S>0);
    consModel.S(sel1)=0;
    consModel.S(sel2)=0;

end