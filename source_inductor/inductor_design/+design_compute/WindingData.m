classdef WindingData < handle
    % Class for managing the litz wire winding material data.
    %
    %    Map the different unique id with the corresponding data.
    %    Get constant properties (mass, cost, current density, etc.).
    %    Get the losses for sinus current (HF losses, with DC biais).
    %    Get the losses for triangular current (HF losses, with DC biais).
    %    The code is completely vectorized.
    %
    %    The input data required by this class require a defined format:
    %        - each material has a unique id
    %        - the material data is generated by 'resources/material/run_winding.m'
    %
    %    (c) 2019-2020, ETH Zurich, Power Electronic Systems Laboratory, T. Guillod
    
    %% properties
    properties (SetAccess = private, GetAccess = public)
        idx % vector: map each sample to an array index corresponding to the material
        param % struct: struct of vectors containing the constant properties for each sample
        interp % cell: cell containing the interpolation object for the different materials
        volume % vector: volume of the material for each sample
        fill_pack % vector: fill factor of the packing (not of the litz wire) for each sample
    end
    
    %% public
    methods (Access = public)
        function self = WindingData(material, id, volume, fill_pack)
            % Constructor.
            %
            %    Parameters:
            %        material (struct): definition of the materials and the corresponding unique id
            %        id (vector): material id of each sample
            %        volume (vector): volume of the material for each sample
            %        fill_pack (vector): fill factor of the packing (not of the litz wire) for each sample
            
            % check that the data are winding data
            assert(strcmp(material.type, 'winding'), 'invalid material type')
            
            % assign input
            for i=1:length(material.data)
                % extract the id to map it later
                id_vec(i) = get_map_str_to_int(material.data{i}.id);
                
                % constant properties
                param_tmp(i) = material.data{i}.material.param;
                
                % create the inperpolation object
                interp_tmp{i} = self.parse_interp(material.data{i}.material.interp);
            end
            
            % create the mapping indices, map the the constant properties with the id
            self.parse_data(id_vec, id, param_tmp);
            
            % assign the data
            self.interp = interp_tmp;
            self.volume = volume;
            self.fill_pack = fill_pack;
        end
        
        function m = get_mass(self)
            % Get the mass of the component (density multiplied with volume).
            %
            %    Returns:
            %        m (vector): mass of the different samples
            
            % total fill factor (litz wire and packing)
            fill = self.param.fill_litz.*self.fill_pack;
            
            % mass per volume
            rho = self.param.rho_copper.*fill+self.param.rho_iso.*(1-fill);
            
            % absolute mass
            m = self.volume.*rho;
        end
        
        function c = get_cost(self)
            % Get the cost of the component (density multiplied with volume and offset).
            %
            %    Returns:
            %        c (vector): cost of the different samples
            
            % total fill factor (litz wire and packing)
            fill = self.param.fill_litz.*self.fill_pack;
            
            % cost per volume
            lambda_copper = self.param.rho_copper.*self.param.kappa_copper;
            lambda_iso = self.param.rho_iso.*self.param.kappa_iso;
            lambda = lambda_copper.*fill+lambda_iso.*(1-fill);
            
            % absolute cost
            c = self.volume.*lambda;
            c = self.param.c_offset+c;
        end
        
        function T_max = get_temperature(self)
            % Get the maximum operating temperature of the component.
            %
            %    Returns:
            %        T_max (vector): maximum operating temperature of the different samples
            
            T_max = self.param.T_max;
        end
        
        function J_rms_max = get_current_density(self)
            % Get the maximum current density of the component.
            %
            %    Returns:
            %        J_rms_max (vector): maximum current density of the different samples
                        
            J_rms_max = self.param.J_rms_max;
        end
        
        function [is_valid, P, P_dc, P_ac_lf, P_ac_hf] = get_losses(self, f_vec, J_freq_vec, H_freq_vec, J_dc, T)
            % Compute the losses with an arbitrary excitation (Fourier).
            %
            %    The following effects are considered.
            %        - temperature dependence of the conductivity
            %        - DC losses
            %        - AC LF losses and AC HF losses (proximity losses)
            %        - details: M. Leibl, "Three-Phase PFC Rectifier and High-Voltage Generator", 2017
            %
            %    The input should have the size of the number of samples.
            %    Peak values are used for the Fourier harmonics.
            %
            %    The signals are given as matrices:
            %        - the columns represents the different samples
            %        - the rows represents the frequency sampling
            %
            %    Parameters:
            %        f_vec (matrix): matrix with the frequencies
            %        J_freq_vec (matrix): matrix with the current density peak harmonics
            %        H_freq_vec (matrix): matrix with the magnetic field peak harmonics
            %        J_dc (vector): DC current density
            %        T (vector): operating temperature
            %
            %    Returns:
            %        is_valid (vector): if the operating points are valid (or not)
            %        P (vector): losses of each sample (density multiplied with volume)
            %        P_dc (vector): DC losses (density multiplied with volume)
            %        P_ac_lf (vector): AC LF losses (density multiplied with volume)
            %        P_ac_hf (vector): AC HF losses (density multiplied with volume)
            
            % parse waveform
            [f, J_ac_rms, H_ac_rms] = self.get_param_waveform(f_vec, J_freq_vec, H_freq_vec);
            
            % get the conductivity
            [is_valid_interp, sigma] = self.get_interp(T);
            
            % get the losses
            [P, P_dc, P_ac_lf, P_ac_hf] = self.get_losses_sub(f, J_ac_rms, H_ac_rms, J_dc, sigma);
            
            % check the validity of the obtained losses
            J_rms_tot = hypot(J_ac_rms, J_dc);
            is_valid_value = self.parse_losses(P, J_rms_tot, f);
            
            % from loss densities to losses
            P = self.volume.*P;
            P_dc = self.volume.*P_dc;
            P_ac_lf = self.volume.*P_ac_lf;
            P_ac_hf = self.volume.*P_ac_hf;
            
            % check validity
            is_valid = is_valid_interp&is_valid_value;
        end
    end
    
    %% private
    methods (Access = private)
        function interp = parse_interp(self, interp)
            % Create the interpolation object for the winding conductivity.
            %
            %    Parameters:
            %        interp (struct): interpolation data
            
            % extract the data
            T_vec = interp.T_vec;
            sigma_vec = interp.sigma_vec;
            
            % create the interpolation in lin scale
            fct_interp = griddedInterpolant(T_vec, sigma_vec, 'linear', 'linear');
            
            % assign the interpolation object
            interp.fct_interp = fct_interp;
        end
        
        function parse_data(self, id_vec, id, param_tmp)
            % Create the mapping indices, map the the constant properties with the id.
            %
            %    Parameters:
            %        id_vec (vector): id of the provided materials
            %        id (vector): material id of each sample
            %        param_tmp (array): array of structs with the constant properties of the provided materials
            
            % map each sample to an array index corresponding to the material
            self.idx = get_integer_map(id_vec, 1:length(id_vec), id);
            
            % merge the constant properties
            param_tmp = get_struct_assemble(param_tmp);
            
            % map the the constant properties with the id
            self.param = get_struct_filter(param_tmp, self.idx);
        end
        
        function [f, J_ac_rms, H_ac_rms] = get_param_waveform(self, f_vec, J_freq_vec, H_freq_vec)
            % Extract the parameters from the frequency domain waveform.
            %
            %    Parameters:
            %        f_vec (matrix): matrix with the frequencies
            %        J_freq_vec (matrix): matrix with the current density peak harmonics
            %        H_freq_vec (matrix): matrix with the magnetic field peak harmonics
            %
            %    Returns:
            %        f (vector): equivalent operating frequency
            %        J_ac_rms (vector): AC RMS current density
            %        H_ac_rms (vector): AC RMS magnetic field
            
            % get the RMS values
            J_ac_rms = sqrt(sum(J_freq_vec.^2, 1))./sqrt(2);
            H_ac_rms = sqrt(sum(H_freq_vec.^2, 1))./sqrt(2);
            
            % get the equivalent operating frequency for the proximity losses
            prox_factor = sqrt(sum(f_vec.^2.*H_freq_vec.^2, 1))./sqrt(2);
            f = prox_factor./H_ac_rms;            
        end
        
        function [P, P_dc, P_ac_lf, P_ac_hf] = get_losses_sub(self, f, J_ac_rms, H_ac_rms, J_dc, sigma)
            % Compute the losses with a a given waveform.
            %
            %    Parameters:
            %        f (vector): frequency excitation vector
            %        J_ac_rms (vector): AC RMS current density
            %        H_ac_rms (vector): AC RMS magnetic field
            %        J_dc (vector): DC current density
            %        sigma (vector): electrical conductivity
            %
            %    Returns:
            %        is_valid (vector): if the operating points are valid (or not)
            %        P (vector): losses of each sample (density multiplied with volume)
            %        P_dc (vector): DC losses (density multiplied with volume)
            %        P_ac_lf (vector): AC LF losses (density multiplied with volume)
            %        P_ac_hf (vector): AC HF losses (density multiplied with volume)
                        
            % compute the skin depth
            delta = self.get_delta(sigma, f);
            
            % get absolute values
            J_dc = abs(J_dc);
            J_ac_rms = abs(J_ac_rms);
            H_ac_rms = abs(H_ac_rms);

            % get the different loss components (DC, AC LF, and AC HF)
            P_dc = self.compute_lf_losses(sigma, J_dc);
            P_ac_lf = self.compute_lf_losses(sigma, J_ac_rms);
            P_ac_hf = self.compute_hf_losses(sigma, delta, H_ac_rms);
            
            % get the total losses and the total RMS current density
            P = P_dc+P_ac_lf+P_ac_hf;
        end
        
        function is_valid = parse_losses(self, P, J_rms_tot, f)
            % Check the validity of loss points.
            %
            %    Parameters:
            %        P (vector): loss density
            %        J_rms_tot (vector): RMS current density (AC and DC)
            %        delta (vector): skin depth
            %
            %    Returns:
            %        is_valid (vector): if the operating points are valid (with the additional checks)
            
            % extract the limit
            P_max = self.param.P_max;
            J_rms_max = self.param.J_rms_max;
            f_max = self.param.f_max;
            
            % check the loss density, the current density, and the skin depth
            is_valid = true;
            is_valid = is_valid&(P<=P_max);
            is_valid = is_valid&(J_rms_tot<=J_rms_max);
            is_valid = is_valid&(f<=f_max);
        end
        
        function delta = get_delta(self, sigma, f)
            % Compute the skin depth.
            %
            %    Parameters:
            %        sigma (vector): electrical conductivity
            %        f (vector): frequency excitation vector
            %
            %    Returns:
            %        delta (vector): skin depth
            
            mu0_const = 4.*pi.*1e-7;
            delta = 1./sqrt(pi.*mu0_const.*sigma.*f);
        end
        
        function P = compute_lf_losses(self, sigma, J_rms)
            % Compute the LF losses.
            %
            %    Parameters:
            %        sigma (vector): electrical conductivity
            %        J_rms (vector): RMS current density
            %
            %    Returns:
            %        P (vector): computed loss densities
            
            % total fill factor (litz wire and packing)
            fill = self.param.fill_litz.*self.fill_pack;
            
            % correct the losses with a factor and the winding fill factor
            fact_tmp = self.param.P_scale_lf./(fill.*sigma);
            
            % compute the losses
            P = fact_tmp.*(J_rms.^2);
        end
        
        function P = compute_hf_losses(self, sigma, delta, H_rms)
            % Compute the HF losses (litz wire proximity effect).
            %
            %    Parameters:
            %        sigma (vector): electrical conductivity
            %        delta (vector): skin depth
            %        H_rms (vector): RMS magnetic field
            %
            %    Returns:
            %        P (vector): computed loss densities
            
            % total fill factor (litz wire and packing)
            fill = self.param.fill_litz.*self.fill_pack;
            
            % proximity loss factor
            gr = (pi.^2.*self.param.d_strand.^6)./(128.*delta.^4);
            
            % correct the losses with a factor and the winding fill factor
            fact_tmp = self.param.P_scale_hf.*gr.*(32.*fill)./(sigma.*pi.^2.*self.param.d_strand.^4);
            
            % compute the losses
            P = fact_tmp.*(H_rms.^2);
        end
                        
        function [is_valid, sigma] = get_interp(self, T)
            % Interpolate electrical conductivities for the different materials.
            %
            %    Parameters:
            %        T (vector): operating temperature
            %
            %    Returns:
            %        is_valid (vector): if the interpolated points are valid (or not)
            %        sigma (vector): interpolated electrical conductivities
            
            % init, nothing is computed
            sigma = NaN(1, length(self.idx));
            is_valid = false(1, length(self.idx));
            
            % for each material, apply the interpolation to the samples with this material
            for i=1:length(self.interp)
                % which samples have this material
                idx_select = self.idx==i;
                
                % get the interpolation
                [is_valid_tmp, P_tmp] = self.get_interp_sub(self.interp{i}, idx_select, T);
                
                % assign to the respective indices
                sigma(idx_select) = P_tmp;
                is_valid(idx_select) = is_valid_tmp;
            end
        end
        
        function [is_valid, sigma] = get_interp_sub(self, interp, idx_select, T)
            % Interpolate electrical conductivities for a specific material.
            %
            %    Parameters:
            %        interp (struct): interpolation data for the selected material
            %        idx_select (vector): indices of the samples having this material
            %        T (vector): operating temperature
            %
            %    Returns:
            %        is_valid (vector): if the interpolated points are valid (or not)
            %        sigma (vector): interpolated electrical conductivities
            
            % filter the samples
            T = T(idx_select);
            
            % clamp the data to avoid extrapolation
            %    - extrapolation of conducitivity not really useful
            %    - if clamped, the points are invalid
            is_valid = true;
            [is_valid, T] = get_clamp(is_valid, T, interp.T_vec);
            
            % run the interpolation
            sigma = interp.fct_interp(T);
        end
    end
end
