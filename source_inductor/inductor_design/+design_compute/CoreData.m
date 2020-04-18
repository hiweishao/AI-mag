classdef CoreData < handle
    % Class for managing the core material data.
    %
    %    Map the different unique id with the corresponding data.
    %    Get constant properties (mass, cost, saturation, etc.).
    %    Get the losses for sinus flux (lossmap, with DC biais).
    %    Get the losses for triangular flux (IGGE, lossmap, with DC biais).
    %    The code is completely vectorized.
    %
    %    The input data required by this class require a defined format:
    %        - each material has a unique id
    %        - the material data is generated by 'resources/material/run_core.m'
    %
    %    (c) 2019-2020, ETH Zurich, Power Electronic Systems Laboratory, T. Guillod
    
    %% properties
    properties (SetAccess = private, GetAccess = public)
        idx % vector: map each sample to an array index corresponding to the material
        param % struct: struct of vectors containing the constant properties for each sample
        interp % cell: cell containing the interpolation object for the different materials
        volume % vector: volume of the material for each sample
    end
    
    %% public
    methods (Access = public)
        function self = CoreData(material, id, volume)
            % Constructor.
            %
            %    Parameters:
            %        material (struct): definition of the materials and the corresponding unique id
            %        id (vector): material id of each sample
            %        volume (vector): volume of the material for each sample

            % check that the data are core data
            assert(strcmp(material.type, 'core'), 'invalid length')
            
            % parse the data for the different materials
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
        end
        
        function m = get_mass(self)
            % Get the mass of the component (density multiplied with volume).
            %
            %    Returns:
            %        m (vector): mass of the different samples
            
            m = self.volume.*self.param.rho;
        end
        
        function c = get_cost(self)
            % Get the cost of the component (density multiplied with volume and offset).
            %
            %    Returns:
            %        c (vector): cost of the different samples

            % cost per volume
            lambda = self.param.rho.*self.param.kappa;
            
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
        
        function B_sat_max = get_flux_density(self)
            % Get the maximum flux density of the component.
            %
            %    Returns:
            %        B_sat_max (vector): maximum flux density of the different samples
            
            B_sat_max = self.param.B_sat_max;
        end
        
        function [is_valid, P] = get_losses_sin(self, f, B_ac_peak, B_dc, T)
            % Compute the losses with a sinus excitation.
            %
            %    Use a loss map (temperature, frequency, AC flux, DC bias).
            %        - interpolation between the loss points
            %        - details: R. Burkart, "Advanced Modeling and Multi-Objective Optimization of Power Electronic Converter Systems", 2016
            %
            %    The input should have the size of the number of samples.
            %
            %    Parameters:
            %        f (vector): frequency excitation vector
            %        B_ac_peak (vector): peak AC flux density
            %        B_dc (vector): DC flux density
            %        T (vector): operating temperature
            %
            %    Returns:
            %        is_valid (vector): if the operating points are valid (or not)
            %        P (vector): losses of each sample (density multiplied with volume)

            % interpolate the loss density
            [is_valid, P] = self.get_interp(f, B_ac_peak, B_dc, T);
            
            % check the validity of the obtained losses
            is_valid = self.parse_losses(is_valid, P, B_ac_peak+B_dc);
            
            % from loss densities to losses
            P = self.volume.*P;
        end
        
        function [is_valid, P] = get_losses_tri(self, f, d_c, B_ac_peak, B_dc, T)
            % Compute the losses with a PWM excitation (triangular flux).
            %
            %    Use a loss map (temperature, frequency, AC flux, DC bias).
            %        - interpolation between the loss points
            %        - extract the local IGSE parameters
            %        - compute the losses with IGSE
            %        - details: K. Venkatachalam, "Accurate Prediction of Ferrite Core Loss with Nonsinusoidal Waveforms Using Only Steinmetz Parameters", 2002
            %        - details: R. Burkart, "Advanced Modeling and Multi-Objective Optimization of Power Electronic Converter Systems", 2016
            %
            %    The input should have the size of the number of samples.
            %
            %    Parameters:
            %        f (vector): frequency excitation vector
            %        d_c (vector): duty cycle of the triangular shape
            %        B_ac_peak (vector): peak AC flux density
            %        B_dc (vector): DC flux density
            %        T (vector): operating temperature
            %
            %    Returns:
            %        is_valid (vector): if the operating points are valid (or not)
            %        P (vector): losses of each sample (density multiplied with volume)
            
            % interpolate the loss map, get the IGSE parameters
            [is_valid, k, alpha, beta] = compute_steinmetz(self, f, B_ac_peak, B_dc, T);
            
            % apply the IGSE and get the loss density
            P = self.compute_steinmetz_losses(k, alpha, beta, f, d_c, B_ac_peak);
            
            % check the validity of the obtained losses
            is_valid = self.parse_losses(is_valid, P, B_ac_peak+B_dc);
            
            % from loss densities to losses
            P = self.volume.*P;
        end
    end
    
    %% private
    methods (Access = private)
        function interp = parse_interp(self, interp)
            % Create the interpolation object for the core loss map.
            %
            %    Parameters:
            %        interp (struct): interpolation data

            % extract the data
            f_vec = interp.f_vec;
            B_ac_peak_vec = interp.B_ac_peak_vec;
            B_dc_vec = interp.B_dc_vec;
            T_vec = interp.T_vec;
            P_mat = interp.P_mat;
            
            % grid the data, make a linear interpolation in log scale
            [f_mat, B_ac_peak_mat, B_dc_mat, T_mat] = ndgrid(f_vec, B_ac_peak_vec, B_dc_vec, T_vec);
            fct_interp = griddedInterpolant(log10(f_mat), log10(B_ac_peak_mat), B_dc_mat, T_mat, log10(P_mat), 'linear', 'linear');
            
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
        
        function is_valid = parse_losses(self, is_valid, P, B_peak_tot)
            % Check the validity of loss points.
            %
            %    Parameters:
            %        is_valid (vector): if the operating points are valid (from the interpolation)
            %        P (vector): loss density
            %        B_peak_tot (vector): peak flux density (AC and DC)
            %
            %    Returns:
            %        is_valid (vector): if the operating points are valid (with the additional checks)

            % extract the limit
            P_max = self.param.P_max;
            B_sat_max = self.param.B_sat_max;
            
            % check the loss density and the peak flux density
            is_valid = is_valid&(P<=P_max);
            is_valid = is_valid&(B_peak_tot<=B_sat_max);
        end
        
        function [is_valid, k, alpha, beta] = compute_steinmetz(self, f, B_ac_peak, B_dc, T)
            % Compute the losses with the Steinmetz parameters from the loss map.
            %
            %    The Steinmetz paramters are extracted with the following methods:
            %        - The losses are computed for: B_ac_peak*(1+eps) and B_ac_peak/(1+eps)
            %        - The losses are computed for: f*(1+eps) and f/(1+eps)
            %        - Then, alpha and represents the gradients (in log scale)
            %        - Finally, k is set in order to get the right absolute value of the losses
            %
            %    Parameters:
            %        f (vector): frequency excitation vector
            %        B_ac_peak (vector): peak AC flux density
            %        B_dc (vector): DC flux density
            %        T (vector): operating temperature
            %
            %    Returns:
            %        is_valid (vector): if the Steinmetz parameters are valid (or not) 
            %        k (vector): Steinmetz parameter k
            %        alpha (vector): Steinmetz parameter alpha
            %        beta (vector): Steinmetz parameter beta
            
            % init, erverything is valid
            is_valid = true;
            
            % compute the points where the gradient should be computed
            fact_igse = self.param.fact_igse;
            f_1 = f.*(1+fact_igse);
            f_2 = f./(1+fact_igse);
            B_ac_peak_1 = B_ac_peak.*(1+fact_igse);
            B_ac_peak_2 = B_ac_peak./(1+fact_igse);
            
            % get the loss of the given points
            [is_valid_tmp, P_ref] = self.get_interp(f, B_ac_peak, B_dc, T);
            is_valid = is_valid&is_valid_tmp;
            
            % points for the frequency gradient
            [is_valid_tmp, P_f_1] = self.get_interp(f_1, B_ac_peak, B_dc, T);
            is_valid = is_valid&is_valid_tmp;
            [is_valid_tmp, P_f_2] = self.get_interp(f_2, B_ac_peak, B_dc, T);
            is_valid = is_valid&is_valid_tmp;
            
            % points for the flux density
            [is_valid_tmp, P_B_ac_peak_1] = self.get_interp(f, B_ac_peak_1, B_dc, T);
            is_valid = is_valid&is_valid_tmp;
            [is_valid_tmp, P_B_ac_peak_2] = self.get_interp(f, B_ac_peak_2, B_dc, T);
            is_valid = is_valid&is_valid_tmp;
            
            % with the gradients and the losses, compute the Steinmetz parameters
            alpha = log(P_f_1./P_f_2)./log(f_1./f_2);
            beta = log(P_B_ac_peak_1./P_B_ac_peak_2)./log(B_ac_peak_1./B_ac_peak_2);
            k = P_ref./((f.^alpha).*(B_ac_peak.^beta));
        end
                
        function P = compute_steinmetz_losses(self, k, alpha, beta, f, d_c, B_ac_peak)
            % Compute the losses with the IGSE (triangular flux).
            %
            %    Parameters:
            %        k (vector): Steinmetz parameter k
            %        alpha (vector): Steinmetz parameter alpha
            %        beta (vector): Steinmetz parameter beta
            %        f (vector): frequency excitation vector
            %        d_c (vector): duty cycle of the triangular shape
            %        B_ac_peak (vector): peak AC flux density
            %
            %    Returns:
            %        P (vector): computed loss densities

            % get the parameter from the Steinmetz parameters
            ki = self.compute_steinmetz_ki(k, alpha, beta);
            
            % peak to peak flux density
            t_1 = d_c./f;
            t_2 = (1-d_c)./f;
            B_ac_peak_ac_peak = 2.*B_ac_peak;
            
            % apply IGSE integral, for the special case of a triangular flux
            v_1 = (abs(B_ac_peak_ac_peak./t_1).^alpha).*t_1;
            v_2 = (abs(B_ac_peak_ac_peak./t_2).^alpha).*t_2;
            v_cst = f.*ki.*B_ac_peak_ac_peak.^(beta-alpha);
            P = v_cst.*(v_1+v_2);
        end
        
        function ki = compute_steinmetz_ki(self, k, alpha, beta)
            % Compute the IGSE parameter from the Steinmetz parameters.
            %
            %    Parameters:
            %        k (vector): Steinmetz parameter k
            %        alpha (vector): Steinmetz parameter alpha
            %        beta (vector): Steinmetz parameter beta
            %
            %    Returns:
            %        ki (vector): IGSE parameter ki
            
            t1 = (2.*pi).^(alpha-1);
            t2 = 2.*sqrt(pi).*gamma(1./2+alpha./2)./gamma(1+alpha./2);
            t3 = 2.^(beta-alpha);
            ki = k./(t1.*t2.*t3);
        end

        function [is_valid, P] = get_interp(self, f, B_ac_peak, B_dc, T)
            % Interpolate losses with the loss map for the different materials.
            %
            %    Parameters:
            %        f (vector): frequency excitation vector
            %        B_ac_peak (vector): peak AC flux density
            %        B_dc (vector): DC flux density
            %        T (vector): operating temperature
            %
            %    Returns:
            %        is_valid (vector): if the interpolated points are valid (or not)
            %        P (vector): interpolated loss densities

            % init, nothing is computed
            P = NaN(1, length(self.idx));
            is_valid = false(1, length(self.idx));
            
            % for each material, apply the interpolation to the samples with this material
            for i=1:length(self.interp)
                % which samples have this material
                idx_select = self.idx==i;
                
                % get the interpolation
                [is_valid_tmp, P_tmp] = self.get_interp_sub(self.interp{i}, idx_select, f, B_ac_peak, B_dc, T);
                
                % assign to the respective indices
                P(idx_select) = P_tmp;
                is_valid(idx_select) = is_valid_tmp;
            end
            
            % scale the loss density with a given factor
            P = self.param.P_scale.*P;
        end
        
        function [is_valid, P] = get_interp_sub(self, interp, idx_select, f, B_ac_peak, B_dc, T)
            % Interpolate losses with the loss map for a specific material.
            %
            %    Parameters:
            %        interp (struct): interpolation data for the selected material
            %        idx_select (vector): indices of the samples having this material
            %        f (vector): frequency excitation vector
            %        B_ac_peak (vector): peak AC flux density
            %        B_dc (vector): DC flux density
            %        T (vector): operating temperature
            %
            %    Returns:
            %        is_valid (vector): if the interpolated points are valid (or not)
            %        P (vector): interpolated loss densities
            
            % filter the samples
            f = f(idx_select);
            B_ac_peak = B_ac_peak(idx_select);
            B_dc = B_dc(idx_select);
            T = T(idx_select);
            
            % clamp the data to avoid extrapolation
            %    - extrapolation of core loss data is dangerous
            %    - if clamped, the points are invalid            
            is_valid = true;
            [is_valid, f] = get_clamp(is_valid, f, interp.f_vec);
            [is_valid, B_ac_peak] = get_clamp(is_valid, B_ac_peak, interp.B_ac_peak_vec);
            [is_valid, B_dc] = get_clamp(is_valid, B_dc, interp.B_dc_vec);
            [is_valid, T] = get_clamp(is_valid, T, interp.T_vec);
            
            % run the interpolation
            P = 10.^interp.fct_interp(log10(f), log10(B_ac_peak), B_dc, T);
        end
    end
end
