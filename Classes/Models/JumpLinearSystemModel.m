classdef JumpLinearSystemModel < SystemModel
    % Implementation of a Jump Linear System consisting of a set of
    % LinearSystemModels, usually refered to as modes, one of which being active at a time.
    % A specific example is a Markov Jump Linear System where the active
    % system model (mode) changes according to a Markov chain.
    
    % >> This function/class is part of CoCPN-Sim
    %
    %    For more information, see https://github.com/spp1914-cocpn/cocpn-sim
    %
    %    Copyright (C) 2016  Florian Rosenthal <florian.rosenthal@kit.edu>
    %
    %                        Institute for Anthropomatics and Robotics
    %                        Chair for Intelligent Sensor-Actuator-Systems (ISAS)
    %                        Karlsruhe Institute of Technology (KIT), Germany
    %
    %                        http://isas.uka.de
    %
    %    This program is free software: you can redistribute it and/or modify
    %    it under the terms of the GNU General Public License as published by
    %    the Free Software Foundation, either version 3 of the License, or
    %    (at your option) any later version.
    %
    %    This program is distributed in the hope that it will be useful,
    %    but WITHOUT ANY WARRANTY; without even the implied warranty of
    %    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    %    GNU General Public License for more details.
    %
    %    You should have received a copy of the GNU General Public License
    %    along with this program.  If not, see <http://www.gnu.org/licenses/>.
    
    properties (SetAccess = immutable, GetAccess = private)
        numModes;
    end
    
    properties (GetAccess = public, SetAccess = private)
        modeSystemModels;
    end
    
    properties (Access = private)
        activeMode;
    end
    
    methods (Access = public)
        %% JumpLinearSystemModel
        function this = JumpLinearSystemModel(numModes, systemModels)
            if ~Checks.isPosScalar(numModes) || mod(numModes, 1) ~= 0
                 error('JumpLinearSystemModel:InvalidNumModes', ...
                    '** Number of modes must be a positive integer **');
            end
            this.numModes = numModes;
            this.setModeSystemModels(systemModels);
            % initially, the system is in mode 1 and no input is applied
            this.setActiveMode(1);
            this.setSystemInput([]);
        end
        
        %% setModeSystemModels
        function setModeSystemModels(this, systemModels)
            if ~iscell(systemModels) || numel(systemModels) < this.numModes ...
                    ||  any(cellfun(@(model) ~Checks.isClass(model, 'LinearSystemModel'), systemModels))
                error('JumpLinearSystemModel:InvalidModeSystemModels', ...
                    '** <systemModels> must be a cell array with at least %d LinearSystemModel(s). **', ...
                        this.numModes);    
            end
            % internally, store models as a row vector-like cell array
            this.modeSystemModels = reshape(systemModels(1:this.numModes), 1, this.numModes);
        end
        
        %% setSystemInput
        function setSystemInput(this, sysInput)
            % Set the system input.
            %
            % By default, the system input is an empty matrix.
            %
            % Parameters:
            %   >> sysInput (Matrix, vector or empty matrix)
            %      A matrix with column-wise arranged mode-specific inputs,
            %      or a single vector for all modes.
            %      An empty matrix means no input vector.
            if Checks.isFixedColMat(sysInput, this.numModes)
                arrayfun(@(mode) this.modeSystemModels{mode}.setSystemInput(sysInput(:, mode)), 1:this.numModes);
            elseif Checks.isVec(sysInput) || isempty(sysInput)
                cellfun(@(model) model.setSystemInput(sysInput), this.modeSystemModels)
            else
                error('JumpLinearSystemModel:InvalidSystemInput', ...
                  ['** <sysInput> must be a matrix with column-wise arranged mode-specific inputs, '...
                  'a single input vector for all modes or an empty matrix **']);
            end
        end
        
         %% getSystemInput
         function input = getSystemInput(this)
            % Get the system input vector applied to each mode of the system.
            %
            % Returns:
            %   << input (Matrix)
            %      A matrix with column-wise arranged mode-specific inputs.
            %      An empty matrix means no input vector.
            input = cell2mat(cellfun(@(model) model.getSystemInput(), this.modeSystemModels, 'UniformOutput', false));
         end
        
        %% setSystemMatrixForMode
        function setSystemMatrixForMode(this, sysMatrix, mode)
            this.checkMode(mode);
            this.modeSystemModels{mode}.setSystemMatrix(sysMatrix);
        end
        
        %% setActiveMode
        function setActiveMode(this, activeMode)
            this.checkMode(activeMode);
            this.activeMode = activeMode;
        end
        
        %% systemEquation
        function predictedStates = systemEquation(this, stateSamples, noiseSamples)
            predictedStates = this.modeSystemModels{this.activeMode}.systemEquation(stateSamples, noiseSamples);
        end
        
        %% simulate
        function predictedState = simulate(this, state)
            % Simulate the temporal evolution for a given system state.
            %
            % Parameters:
            %   >> state (Column vector)
            %      The system state to predict.
            %
            % Returns:
            %   << predictedState (Column vector)
            %      The simulated temporal system state evolution.
            
            predictedState = this.modeSystemModels{this.activeMode}.simulate(state);
        end
        
        %% isMeanSquareStable
        function mss = isMeanSquareStable(this, transitionMatrix)
            Validator.validateTransitionMatrix(transitionMatrix, this.numModes);
            
            dimState = size(this.modeSystemModels{this.activeMode}.sysMatrix, 1);
            blocks = cellfun(@(model) kron(model.sysMatrix, model.sysMatrix),...
                this.modeSystemModels, 'UniformOutput', false);
            mss = max(abs(eig(blkdiag(blocks{:}) * kron(transitionMatrix', speye(dimState ^ 2))))) < 1;
        end
    end
    
    methods(Access = private)
        function checkMode(this, mode)
            if ~Checks.isScalarIn(mode, 1, this.numModes) || mod(mode, 1) ~= 0
                error('JumpLinearSystemModel:InvalidMode', ...
                    '** mode must be from {1, ..., %d}. **', this.numModes);
            end
        end
    end
end

