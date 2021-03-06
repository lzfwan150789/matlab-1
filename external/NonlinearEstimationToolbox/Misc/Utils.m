
classdef Utils
    % This class provides various utility functions.
    %
    % Utils Methods:
    %   getMeanAndCov                  - Compute sample mean and sample covariance.
    %   getGMMeanAndCov                - Compute mean and covariance matrix of a Gaussian mixture.
    %   kalmanUpdate                   - Perform a Kalman update.
    %   decomposedStateUpdate          - Perform an update for a system state decomposed into two parts A and B.
    %   blockDiag                      - Create a block diagonal matrix.
    %   drawGaussianRndSamples         - Draw random samples from a multivariate Gaussian distribution.
    %   diffQuotientState              - Compute first-order and second-order difference quotients of a function at the given nominal system state.
    %   diffQuotientStateAndNoise      - Compute first-order and second-order difference quotients of a function at the given nominal system state and nominal noise.
    %   diffQuotientStateInputAndNoise - Compute first-order and second-order difference quotients of a function at the given nominal system state, nominal input and nominal noise.
    
    % >> This function/class is part of the Nonlinear Estimation Toolbox
    %
    %    For more information, see https://bitbucket.org/nonlinearestimation/toolbox
    %
    %    Copyright (C) 2015-2017  Jannik Steinbring <nonlinearestimation@gmail.com>
    %                             Florian Rosenthal <florian.rosenthal@kit.edu>
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
    
    methods (Static)
        function [mean, cov] = getMeanAndCov(samples, weights)
            % Compute sample mean and sample covariance.
            %
            % Parameters:
            %   >> samples (Matrix)
            %      Column-wise arranged samples.
            %
            %   >> weights (Row vector)
            %      Column-wise arranged corresponding normalized sample weights.
            %      If no weights are passed, all samples are assumed
            %      to be equally weighted.
            %
            % Returns:
            %   << mean (Column vector)
            %      The sample mean.
            %
            %   << cov (Positive definite matrix)
            %      The sample covariance matrix.
            
            if nargin < 2
                numSamples = size(samples, 2);
                
                % Compute mean
                mean = sum(samples, 2) / numSamples;
                
                % Compute covariance
                if nargout > 1
                    diffSamples = bsxfun(@minus, samples, mean);
                    
                    cov = (diffSamples * diffSamples') / numSamples;
                end
            else
                % Compute mean
                mean = samples * weights';
                
                % Compute covariance
                if nargout > 1
                    diffSamples = bsxfun(@minus, samples, mean);
                    
                    % Weights can be negative => we have to treat them separately
                    
                    % Positive weights
                    idx = weights >= 0;
                    
                    sqrtWeights         = sqrt(weights(idx));
                    weightedDiffSamples = bsxfun(@times, diffSamples(:, idx), sqrtWeights);
                    
                    cov = weightedDiffSamples * weightedDiffSamples';
                    
                    % Negative weights
                    if ~all(idx)
                        idx = ~idx;
                        
                        sqrtWeights         = sqrt(abs(weights(idx)));
                        weightedDiffSamples = bsxfun(@times, diffSamples(:, idx), sqrtWeights);
                        
                        cov = cov - weightedDiffSamples * weightedDiffSamples';
                    end
                end
            end
        end
        
        function [mean, cov] = getGMMeanAndCov(means, covariances, weights)
            % Compute mean and covariance matrix of a Gaussian mixture.
            %
            % Parameters:
            %   >> means (Matrix)
            %      Column-wise arranged means of the Gaussian mixture components.
            %
            %   >> covariances (3D matrix containing positive definite matrices)
            %      Slice-wise arranged covariance matrices of the Gaussian mixture components.
            %
            %   >> weights (Row vector)
            %      Row-wise arranged normalized weights of the Gaussian mixture components.
            %      If no weights are passed, all Gaussian mixture components are assumed to be equally weighted.
            %
            % Returns:
            %   << mean (Column vector)
            %      The mean of the Gaussian mixture.
            %
            %   << cov (Positive definite matrix)
            %      The covariance matrix of the Gaussian mixture.
            
            numComponents = size(means, 2);
            
            if nargin < 3
                [mean, covMeans] = Utils.getMeanAndCov(means);
                
                cov = covMeans + sum(covariances, 3) / numComponents;
            else
                [mean, covMeans] = Utils.getMeanAndCov(means, weights);
                
                weightedCovs = bsxfun(@times, covariances, ...
                                      reshape(weights, [1 1 numComponents]));
                
                cov = covMeans + sum(weightedCovs, 3);
            end
        end
                
        function [updatedStateMean, ...
                  updatedStateCov, ...
                  sqMeasMahalDist] = kalmanUpdate(stateMean, stateCov, measurement, ...
                                                  measMean, measCov, stateMeasCrossCov)
            % Perform a Kalman update.
            %
            % Parameters:
            %   >> stateMean (Column vector)
            %      Prior state mean.
            %
            %   >> stateCov (Positive definite matrix)
            %      Prior state covariance matrix.
            %
            %   >> measurement (Column vector)
            %      Measurement vector.
            %
            %   >> measMean (Column vector)
            %      Measurement mean.
            %
            %   >> measCov (Positive definite matrix)
            %      Measurement covariance matrix.
            %
            %   >> stateMeasCrossCov (Matrix)
            %      State measurement cross-covariance matrix.
            %
            % Returns:
            %   << updatedStateMean (Column vector)
            %      Posterior state mean.
            %
            %   << updatedStateCov (Positive definite matrix)
            %      Posterior state covariance matrix.
            %
            %   << sqMeasMahalDist (Scalar)
            %      Squared Mahalanobis distance of the measurement.
            
            [measCovSqrt, isNonPos] = chol(measCov, 'Lower');
            
            if isNonPos
                error('Utils:InvalidMeasurementCovariance', ...
                      'Measurement covariance matrix is not positive definite.');
            end
            
            A = stateMeasCrossCov / measCovSqrt';
            
            innovation = measurement - measMean;
            
            t = measCovSqrt \ innovation;
            
            % Compute updated state mean
            updatedStateMean = stateMean + A * t;
            
            % Compute updated state covariance
            updatedStateCov = stateCov - A * A';
            
            % Compute squared Mahalanobis distance of the measurement
            if nargout == 3
                sqMeasMahalDist = t' * t;
            end
        end
        
        function [updatedStateMean, ...
                  updatedStateCov] = decomposedStateUpdate(stateMean, stateCov, stateCovSqrt, ...
                                                           updatedStateMeanA, updatedStateCovA, updatedStateCovASqrt)
            % Perform an update for a system state decomposed into two parts A and B.
            %
            % Parameters:
            %   >> stateMean (Column vector)
            %      Prior mean of the entire state.
            %
            %   >> stateCov (Positive definite matrix)
            %      Prior covariance matrix of the entire state.
            %
            %   >> stateCovSqrt (Square matrix)
            %      Square root of the prior covariance matrix.
            %
            %   >> updatedStateMeanA (Column vector)
            %      Already updated mean of subspace A.
            %
            %   >> updatedStateCovA (Positive definite matrix)
            %      Already updated covariance matrix of subspace A.
            %
            %   >> updatedStateCovASqrt (Square matrix)
            %      Square root of the already updated covariance matrix of subspace A.
            %
            % Returns:
            %   << updatedStateMean (Column vector)
            %      Posterior mean of the entire state.
            %
            %   << updatedStateCov (Positive definite matrix)
            %      Posterior covariance matrix of the entire state.
            
            D = size(updatedStateMeanA, 1);
            
            priorStateMeanA    = stateMean(1:D);
            priorStateMeanB    = stateMean(D+1:end);
            priorStateCovA     = stateCov(1:D, 1:D);
            priorStateCovB     = stateCov(D+1:end, D+1:end);
            priorStateCovBA    = stateCov(D+1:end, 1:D);
            priorStateCovASqrt = stateCovSqrt(1:D, 1:D);
            
            % Computed updated mean, covariance, and cross-covariance for the subspace B
            K = priorStateCovBA / priorStateCovA;
            A = K * updatedStateCovASqrt;
            B = K * priorStateCovASqrt;
            updatedStateMeanB = priorStateMeanB + K * (updatedStateMeanA - priorStateMeanA);
            updatedStateCovB  = priorStateCovB + A * A' - B * B';
            updatedStateCovBA = K * updatedStateCovA;
            
            % Construct updated state mean and covariance
            updatedStateMean = [updatedStateMeanA
                                updatedStateMeanB];
            
            updatedStateCov = [updatedStateCovA  updatedStateCovBA'
                               updatedStateCovBA updatedStateCovB  ];
        end
        
        function blockMat = blockDiag(matrix, numRepetitions)
            % Create a block diagonal matrix.
            %
            % Parameters:
            %   >> matrix (Matrix)
            %      Matrix.
            %
            %   >> numRepetitions (Positive scalar)
            %      Number of matrix repetitions along the diagonal.
            %
            % Returns:
            %   << blockMat (Matrix)
            %      Block diagonal matrix.
            
            blockMat = kron(speye(numRepetitions), matrix);
        end
                
        
        function rndSamples = drawGaussianRndSamples(mean, covSqrt, numSamples)
            % Draw random samples from a multivariate Gaussian distribution.
            %
            % Parameters:
            %   >> mean (Column vector)
            %      Mean vector.
            %
            %   >> covSqrt (Square matrix)
            %      Square root of the covariance matrix.
            %
            %   >> numSamples (Positive scalar)
            %      Number of samples to draw from the given Gaussian distribution.
            %
            % Returns:
            %   << rndSamples (Matrix)
            %      Column-wise arranged samples drawn from the given Gaussian distribution.
            
            dim = size(mean, 1);
            
            rndSamples = covSqrt * randn(dim, numSamples);
            
            rndSamples = bsxfun(@plus, rndSamples, mean);
        end
                
        function [stateJacobian, stateHessians] = diffQuotientState(func, nominalState, step)
            % Compute first-order and second-order difference quotients of a function at the given nominal system state.
            %
            % Parameters:
            %   >> func (Function handle)
            %      System/Measurement function.
            %
            %   >> nominalState (Column vector)
            %      Nominal system state.
            %
            %   >> step (Positive scalar)
            %      Step size for computing the difference quotients.
            %      Default: eps^(1/4)
            %
            % Returns:
            %   << stateJacobian (Square matrix)
            %      First-order difference quotients of the system state
            %      variables, i.e., an approximation of the Jacobian.
            %
            %   << stateHessians (3D matrix)
            %      Set of second-order difference quotients of the system
            %      state variables, i.e., approximations of the Hessians.
            
            % Default value for step
            if nargin < 3
                step = eps^(1/4);
            end
            
            dimState = size(nominalState, 1);
            
            % State Jacobian
            stateSamples = Utils.getJacobianSamples(dimState, nominalState, step);
            
            valuesState = func(stateSamples);
            
            stateJacobian = Utils.getJacobian(dimState, valuesState, step);
            
            if nargout == 2
                % State Hessians
                [stateSamples, L] = Utils.getHessiansSamples(dimState, nominalState, step);
                
                valuesState2 = func(stateSamples);
                
                stateHessians = Utils.getHessians(dimState, valuesState, valuesState2, L, step);
            end
        end
        
        function [stateJacobian, noiseJacobian, ...
                  stateHessians, noiseHessians] = diffQuotientStateAndNoise(func, nominalState, nominalNoise, step)
            % Compute first-order and second-order difference quotients of a function at the given nominal system state and nominal noise.
            %
            % Parameters:
            %   >> func (Function handle)
            %      System/Measurement function.
            %
            %   >> nominalState (Column vector)
            %      Nominal system state.
            %
            %   >> nominalNoise (Column vector)
            %      Nominal noise.
            %
            %   >> step (Positive scalar)
            %      Step size to compute the finite difference.
            %      Default: eps^(1/4)
            %
            % Returns:
            %   << stateJacobian (Square matrix)
            %      First-order difference quotients of the system state
            %      variables, i.e., an approximation of the Jacobian.
            %
            %   << noiseJacobian (Square matrix)
            %      First-order difference quotients of the noise variables,
            %      i.e., an approximation of the Jacobian.
            %
            %   << stateHessians (3D matrix)
            %      Set of second-order difference quotients of the system
            %      state variables, i.e., approximations of the Hessians.
            %
            %   << noiseHessians (3D matrix)
            %      Set of second-order difference quotients of the noise
            %      variables, i.e., approximations of the Hessians.
            
            % Default value for step
            if nargin < 4
                step = eps^(1/4);
            end
            
            dimState = size(nominalState, 1);
            dimNoise = size(nominalNoise, 1);
            
            % State Jacobian
            stateSamples = Utils.getJacobianSamples(dimState, nominalState, step);
            noiseSamples = repmat(nominalNoise, 1, 2 * dimState + 1);
            
            valuesState = func(stateSamples, noiseSamples);
            
            stateJacobian = Utils.getJacobian(dimState, valuesState, step);
            
            % Noise Jacobian
            noiseSamples = Utils.getJacobianSamples(dimNoise, nominalNoise, step);
            stateSamples = repmat(nominalState, 1, 2 * dimNoise + 1);
            
            valuesNoise = func(stateSamples, noiseSamples);
            
            noiseJacobian = Utils.getJacobian(dimNoise, valuesNoise, step);
            
            if nargout == 4
                % State Hessians
                [stateSamples, L] = Utils.getHessiansSamples(dimState, nominalState, step);
                noiseSamples = repmat(nominalNoise, 1, 2 * L);
                
                valuesState2 = func(stateSamples, noiseSamples);
                
                stateHessians = Utils.getHessians(dimState, valuesState, valuesState2, L, step);
                
                % Noise Hessians
                [noiseSamples, L] = Utils.getHessiansSamples(dimNoise, nominalNoise, step);
                stateSamples = repmat(nominalState, 1, 2 * L);
                
                valuesNoise2 = func(stateSamples, noiseSamples);
                
                noiseHessians = Utils.getHessians(dimNoise, valuesNoise, valuesNoise2, L, step);
            end
        end
        
        function [stateJacobian, inputJacobian, noiseJacobian, ...
                  stateHessians, inputHessians, noiseHessians] = diffQuotientStateInputAndNoise(func, nominalState, nominalInput, nominalNoise, step)
            % Compute first-order and second-order difference quotients of a function at the given nominal system state, nominal input and nominal noise.
            %
            % Parameters:
            %   >> func (Function handle)
            %      System/Measurement function.
            %
            %   >> nominalState (Column vector)
            %      Nominal system state.
            %
            %   >> nominalInput (Column vector)
            %      Nominal input.
            %
            %   >> nominalNoise (Column vector)
            %      Nominal noise.
            %
            %   >> step (Positive scalar)
            %      Step size to compute the finite difference.
            %      Default: eps^(1/4)
            %
            % Returns:
            %   << stateJacobian (Square matrix)
            %      First-order difference quotients of the system state
            %      variables, i.e., an approximation of the Jacobian.
            %
            %   << inputJacobian (Square matrix)
            %      First-order difference quotients of the input
            %      variables, i.e., an approximation of the Jacobian.
            %
            %   << noiseJacobian (Square matrix)
            %      First-order difference quotients of the noise variables,
            %      i.e., an approximation of the Jacobian.
            %
            %   << stateHessians (3D matrix)
            %      Set of second-order difference quotients of the system
            %      state variables, i.e., approximations of the Hessians.
            %
            %   << inputHessians (3D matrix)
            %      Set of second-order difference quotients of the input
            %      variables, i.e., approximations of the Hessians.
            %
            %   << noiseHessians (3D matrix)
            %      Set of second-order difference quotients of the noise
            %      variables, i.e., approximations of the Hessians.
                            
            % Default value for step
            if nargin < 5
                step = eps^(1/4);
            end
            
            dimState = size(nominalState, 1);
            dimInput = size(nominalInput, 1);
            dimNoise = size(nominalNoise, 1);
            
            % State Jacobian
            states = Utils.getJacobianSamples(dimState, nominalState, step);
            inputSamples = repmat(nominalInput, 1, 2 * dimState + 1);
            noiseSamples = repmat(nominalNoise, 1, 2 * dimState + 1);
            
            valuesState = func(states, inputSamples, noiseSamples);
            stateJacobian = Utils.getJacobian(dimState, valuesState, step);
            
            % Input Jacobian
            inputs = Utils.getJacobianSamples(dimInput, nominalInput, step);
            stateSamples = repmat(nominalState, 1, 2 * dimInput + 1);
            noiseSamples = repmat(nominalNoise, 1, 2 * dimInput + 1); 
            
            valuesInput = func(stateSamples, inputs, noiseSamples);
            inputJacobian = Utils.getJacobian(dimInput, valuesInput, step);
            
            % Noise Jacobian
            noises = Utils.getJacobianSamples(dimNoise, nominalNoise, step);
            stateSamples = repmat(nominalState, 1, 2 * dimNoise + 1);
            inputSamples = repmat(nominalInput, 1, 2 * dimNoise + 1);
            
            valuesNoise = func(stateSamples, inputSamples, noises);
            noiseJacobian = Utils.getJacobian(dimNoise, valuesNoise, step);
            
            if nargout == 6
                % State Hessians
                [states, L] = Utils.getHessiansSamples(dimState, nominalState, step);
                noiseSamples = repmat(nominalNoise, 1, 2 * L);
                inputSamples = repmat(nominalInput, 1, 2 * L);
                
                valuesState2 = func(states, inputSamples, noiseSamples);
                
                stateHessians = Utils.getHessians(dimState, valuesState, valuesState2, L, step);
                
                % Input Hessians
                [inputs, L] = Utils.getHessiansSamples(dimInput, nominalInput, step);
                stateSamples = repmat(nominalState, 1, 2 * L);
                noiseSamples = repmat(nominalNoise, 1, 2 * L);
                
                valuesInput2 = func(stateSamples, inputs, noiseSamples);
                
                inputHessians = Utils.getHessians(dimInput, valuesInput, valuesInput2, L, step);
                
                % Noise Hessians
                [noises, L] = Utils.getHessiansSamples(dimNoise, nominalNoise, step);
                inputSamples = repmat(nominalInput, 1, 2 * L);
                stateSamples = repmat(nominalState, 1, 2 * L);
                
                valuesNoise2 = func(stateSamples, inputSamples, noises);
                
                noiseHessians = Utils.getHessians(dimNoise, valuesNoise, valuesNoise2, L, step);
            end
        end
    end
    
    methods (Static, Access = 'private')
        function samples = getJacobianSamples(dim, nominalVec, step)
            samples = bsxfun(@plus, [step*eye(dim) -step*eye(dim) zeros(dim, 1)], nominalVec);
        end
        
        function jacobian = getJacobian(dim, values, step)
            idx      = 1:dim;
            jacobian = values(:, idx) - values(:, dim + idx);
            jacobian = jacobian / (2 * step);
        end
        
        function [samples, L] = getHessiansSamples(dim, nominalVec, step)
            L     = (dim * (dim + 1)) * 0.5 - dim;
            steps = zeros(dim, L);
            
            a = 1;
            b = dim - 1;
            for i = 1:dim - 1
                d = dim - i;
                
                steps(i,         a:b) = step;
                steps(i + 1:end, a:b) = step * eye(d);
                
                a = b + 1;
                b = a + d - 2;
            end
            
            samples = bsxfun(@plus, [steps -steps], nominalVec);
        end
        
        function hessians = getHessians(dim, values, values2, L, step)
            idx = 1:dim;
            a   = 2 * values(:, end);
            b   = bsxfun(@plus, values2(:, 1:L) + values2(:, L + 1:end), a);
            c   = values(:, idx) + values(:, dim + idx);
            d   = bsxfun(@minus, c, a);
            
            dimFunc  = size(values, 1);
            hessians = nan(dim, dim, dimFunc);
            
            k = 1;
            for i = 1:dim
                hessians(i, i, :) = d(:, i);
                
                for j = (i + 1):dim
                    vec = (b(:, k) - c(:, i) - c(:, j)) * 0.5;
                    
                    hessians(i, j, :) = vec;
                    hessians(j, i, :) = vec;
                    
                    k = k + 1;
                end
            end
            
            hessians = hessians / (step * step);
        end
    end
end
