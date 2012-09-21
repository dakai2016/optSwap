function [newProb,solverParams] = setParams(prob, cobraSolverFlag)

% OPTIONAL
% cobraSolverFlag - setup for solveCobraMILP

    intTol = 10e-9;
    relMipGapTol = 1e-6; 
    timeLimit = 3600*3; %seconds
    logFile = 'log.txt'; 
    printLevel = 10;
    feasTol = 1e-8; 
    optTol = 1e-8; 
    NUMERICALEMPHASIS = 1; 
    absMipGapTol = 1e-8;
    
    if nargin < 2
        cobraSolverFlag = 0;
    end

    if cobraSolverFlag
        newProb = prob;
        
        solverParams.intTol = intTol;
        solverParams.relMipGapTol = relMipGapTol;
        solverParams.timeLimit = timeLimit;
        solverParams.logFile = logFile;
        solverParams.printLevel = printLevel;
        solverParams.feasTol = feasTol;
        solverParams.optTol = optTol;
        solverParams.NUMERICALEMPHASIS = NUMERICALEMPHASIS;
        solverParams.absMipGapTol = absMipGapTol;
        
    else

        newProb=prob;
        newProb.Solver.Alg = 2; % Depth First, then Breadth (Default Depth
                                % First)
                                % 2: Depth first. When integer solution found, switch to Breadth.
        newProb.optParam.MaxIter = 100000; %100000
        % Must increase iterations from default 500
        
        newProb.optParam.IterPrint = 0;
        newProb.PriLev = printLevel;
        newProb.MIP.cpxControl.EPINT=intTol;
        newProb.MIP.cpxControl.EPOPT=optTol;
        newProb.MIP.cpxControl.EPRHS=feasTol;
        newProb.MIP.cpxControl.EPGAP=relMipGapTol;
        newProb.MIP.cpxControl.EPAGAP=absMipGapTol;
        newProb.MIP.cpxControl.NUMERICALEMPHASIS = ...
            NUMERICALEMPHASIS;
        newProb.MIP.cpxControl.SCAIND=1;
        newProb.MIP.cpxControl.TILIM=timeLimit;

    end

end