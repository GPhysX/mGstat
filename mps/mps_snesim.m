% mps_snesim: Multiple point simuation through sequential simulation
%      using SNESIM
%
% Call
%    mps_snesim(TI,SIM,options)
%
%  TI: [ny,nx] 2D training image (categorical variables
%  SIM: [ny2,nx2] 2D simulation grid. 'NaN' indicates an unkown value
%
%  options [struct] optional:
%
%  options.type [string] : 'snesim'
%  options.n_cond [int]: number of conditional points (def=5)
%  options.rand_path [int]: [1] random path (default), [0] sequential path
%  options.n_mulgrids=1; % Number og muliple grids
%
%  % specific for options.type='sneism';
%  options.n_template [int]: template size
%  options.storage_type [str]: 'tree';
%
%
%  options.plot    [int]: [0]:none, [1]:plot cond, [2]:storing movie (def=0)
%  options.verbose [int]: [0] no info to screen, [1]:some info (def=1)
%  % approximating the ocnditional pd:
%  options.n_max_condpd=10; % build conditional pd from max 10 counts
%
%
% %% Example
% TI=channels;
% SIM=ones(40,40)*NaN;
%
% options.n_cond=5;;
% options.n_template=16;;
% [out_dsim]=mps_snesim(TI,SIM,options)
%
%
% See also: mps_enesim, mps_dsim, mps, mps_tree_populate, mps_tree_get_cond
%
function [out,options]=mps_dsim(TI_data,SIM_data,options)
out=[];
if nargin<3
  options.null='';
end

if ~isfield(options,'type');options.type='snesim';end
if ~isfield(options,'storage_type');options.storage_type='tree';end
if ~isfield(options,'verbose');options.verbose=0;end

if ~isfield(options,'n_cond');options.n_cond=5;end

if ~isfield(options,'n_mulgrids');options.n_mulgrids=1;end

if ~isfield(options,'rand_path');options.rand_path=1;end

if ~isfield(options,'compute_entropy');options.compute_entropy=0;end


% OLD
if ~isfield(options,'plot');options.plot=1;end
if ~isfield(options,'plot_interval');options.plot_interval=1;end

%options.N=SIM_data.*0.*NaN;
%options.N_DROPPED=zeros(size(SIM_data));;


%% SET SOME DATA STRICTURES

TI.D=TI_data;
[TI.ny,TI.nx]=size(TI.D);
TI.x=1:1:TI.nx;
TI.y=1:1:TI.ny;
N_TI=numel(TI.D);

SIM.D=SIM_data;
[SIM.ny,SIM.nx]=size(SIM.D);
SIM.x=1:1:SIM.nx;
SIM.y=1:1:SIM.ny;
N_SIM=numel(SIM.D);


% PRE ALLOCATE MATRIX WITH COUNTS
options.C=zeros(size(SIM.D));
options.IPATH=zeros(size(SIM.D));

%% SET TEMPLATE
if ~isfield(options,'T');
  if ~isfield(options,'n_template');options.n_template=48;end;
  n_dim=ndims(SIM);
  options.T=mps_template(options.n_template,n_dim,0);
end

%% CHECK FOR MULTIPLE GRIDS
if options.n_mulgrids>0
  
  %for i_grid=1:(options.n_mulgrids);
  d_cell=2.^([(options.n_mulgrids-1):-1:0]);
  %end
  
  if ~isfield(options,'ST_mul')
    for i_grid=1:(options.n_mulgrids);   
      mgstat_verbose(sprintf('%s: Building tree for MultiGrid #%d d_cell=%d',mfilename,i_grid,d_cell(i_grid)),-1);
      [options.ST_mul{i_grid}]=mps_tree_populate(TI.D,options.T,d_cell(i_grid));
    end
  end
  
  for i_grid=1:(options.n_mulgrids);
    
    ix=d_cell(i_grid):d_cell(i_grid):SIM.nx;
    iy=d_cell(i_grid):d_cell(i_grid):SIM.ny;
    %iz=d_cell(i_grid):d_cell(i_grid):SIM.nz;
    
    SIM_mul=SIM.D(iy,ix);
    %TI_mul=TI.D(d_cell(i_grid):d_cell(i_grid):TI.ny,d_cell(i_grid):d_cell(i_grid):TI.nx);
    
    options_mul=options;
    options_mul.n_mulgrids=0;
 
    
    options_mul.ST=options.ST_mul{i_grid};
    mgstat_verbose(sprintf('%s: simulating on MultiGrid #%d d_cell=%d',mfilename,i_grid,d_cell(i_grid)),-1);      
    [out_mul,o]=mps_snesim(TI.D,SIM_mul,options_mul);
    
    SIM.D(iy,ix)=out_mul;
    options.C(iy,ix)=o.C;
    options.IPATH(iy,ix)=o.IPATH;
    
    %figure(4);subplot(1,length(d_cell),i_grid);imagesc(SIM.D);axis image;caxis([-1 1]);
   
  end
  
  out=SIM.D;
  return
  
end



%% POPULATE SEARCH TREE
if ~isfield(options,'ST');
  mgstat_verbose(sprintf('%s: start building search tree',mfilename),-1)
  tic;
  [options.ST]=mps_tree_populate(TI.D,options.T);
  toc;
  mgstat_verbose(sprintf('%s: end building search tree (%g s)',mfilename,toc),-1)
else
  mgstat_verbose(sprintf('%s: using supplied search tree',mfilename),-1)
end

%% OPEN HANDLE FOR WRITING MOVIE
%if options.plot>2
%    writerObj = VideoWriter('dsim');
%    writerObj.FrameRate=30;
%    writerObj.Quality=90;
%    open(writerObj);
%end



%% SET RANDOM PATH
% find a list of indexes of unsampled values
i_path=find(isnan(SIM.D));
if options.rand_path==1
  % 'SHUFFLE' index of path to get a random path
  i_path=shuffle(i_path);
end
N_PATH=length(i_path);


%% BIG LOOP OVER RANDOM PATH

for i=1:N_PATH; %  % START LOOOP OVER PATH
  
  
  if options.verbose>0
    if ((i/100)==round(i/100))&(options.plot>-1)
      %progress_txt(i,N_SIM,mfilename);
      %progress_txt(i,N_PATH,mfilename);
      disp(sprintf('%s: %03d/%02d',mfilename,i,N_PATH))
    end
  end
  
  % find index of the current node
  i_node=i_path(i);
  [iy,ix]=ind2sub_2d([SIM.ny,SIM.nx],i_node);
  if options.verbose>1
    fprintf('i=%d, at node iy,ix=[%3d,%3d]\n',i,iy,ix);
  end
  options.IPATH(iy,ix)=i;
  
  % only sim if center note is NaN
  if isnan(SIM.D(iy,ix));
    
    % find conditional data
    iz=1; % 2D for now
    [d_cond,n_cond]=mps_cond_from_template(SIM.D,ix,iy,iz,options.T,options.n_cond);
    options.C(iy,ix)=n_cond;
    
    % get conditinal pdf from search tree
    tic
    [c_pdf]=mps_tree_get_cond(options.ST,d_cond);
    options.C(iy,ix)=toc;
    
    % simulate from search tree
    sim_val=min(find(cumsum(c_pdf)>rand(1)))-1;
    try
      SIM.D(iy,ix)=sim_val;
    catch
      keyboard
    end
    
    
    
    %% COMPUTE ENTROPY
    if options.compute_entropy==1;
      options.E(iy,ix)=entropy(c_pdf);
    end
    
  end
  
  % PLOT START
  if options.plot>0
    if ~exist('im')
      figure_focus(2);
      subplot(1,2,1);
      im=imagesc(TI.D);axis image;
      caxis([-1 1]);
    end
    if exist('im_sim')
      if ((i==N_PATH)|((i/options.plot_interval)==round(i/options.plot_interval)))
        set(im_sim,'Cdata',SIM.D);
        drawnow;
      end
    else
      figure_focus(2);
      subplot(1,2,2);
      im_sim=imagesc(SIM.D);
      caxis([-1 1]);
      colormap(cmap_linear([1 1 1 ; 0 0 0; 1 0 0]))
      axis image
    end
    if options.plot>1
      subplot(1,2,2);
      hold on
      im_sim=imagesc(SIM.D);
      caxis([-1 1]);
      colormap(cmap_linear([1 1 1 ; 0 0 0; 1 0 0]))
      axis image
      plot(ix,iy,'go','MarkerSize',12)
      for l=1:size(L,1)
        plot([ix ix+L(l,2)],[iy iy+L(l,1)],'g-')
      end
      hold off
      
    end
    
    if options.plot>1
      subplot(1,2,1);
      im=imagesc(TI.D);axis image;
      caxis([-1 1]);
      hold on
      plot(ix_ti_min,iy_ti_min,'go','MarkerSize',12)
      for l=1:size(L,1)
        plot([ix_ti_min ix_ti_min+L(l,2)],[iy_ti_min iy_ti_min+L(l,1)],'g-')
      end
      hold off
      %disp('paused - hit keyboard');pause;
    end
    
    
    if options.plot>2
      frame = getframe(gcf);
      writeVideo(writerObj,frame);
    end
  end
  %% PLOT END
  
  
end % END LOOOP OVER PATH

if options.plot>2
  try
    close(writerObj);
  catch
    fprintf('%s : coule not close writerObj',mfilename);
  end
end
out=SIM.D;