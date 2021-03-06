function [pcd, outNet, trnEvo, efficVec] = npcd(net, inTrn, inVal, inTst, numIterations, minDiff, nPCD)
%function [pcd, outNet, trnEvo, efficVec] = npcd(net, inTrn, inVal, inTst, numIterations, minDiff, nPCD)
%Extracts the Principal Components of Discrimination (PCD).
%Input parameters are:
% net - The template neural netork to use. The number of PCDs to be
% extracted will be the same as the number of nodes in the first hidden
% layer.
% inTrn - The training data set, organized as a cell vector.
% inVal - The validating data set, organized as a cell vector.
% inTst - The testing data set, organized as a cell vector.
% numIterations - The number of times a neural network should be trained
% for extracting a given PCD. This is used to avoid local minima. For each
% PCD, the iteration which generated the best mean detection efficiency will
% provide the extracted PCD. Default is 10.
% minDiff - The minimum difference (in percentual value) in the SP for continuing extracting PCDs.
% nPCD - If not zero, it must be the numer of OCD to be extracted. This parameter, if > 0, overrides
%        minDiff.
%
%The function returns:
% pcd - A matrix with the extracted PCDs.
% outNet - A cell vector containing the trained network structure obtained after
% each PCD extraction.
% trnEvo - A cell vector containing the training evolution data obtained during
% each PCD extraction.
% efficVec - a struct vector containing the mean and std of the SP efficiency obtained
% for each PCD extraction, considering the number of iterations performed.
%
%

if (nargin < 5), numIterations = 5; end
if (nargin < 6), minDiff = 0.01; end
if (nargin < 7), nPCD = 0; end


if (nargin > 7) || (nargin < 4),
  error('Invalid number of input arguments. See help.');
end

%Getting the desired network parameters.
[trnAlgo, maxNumPCD, numNodes, trfFunc, usingBias, trnParam] = getNetworkInfo(net);
if nPCD > 0,
  maxNumPCD = nPCD;
end

%If we have more than 2 layers (excluding the input), then we'll perform
%PCD extraction based on Caloba's rules, ensuring full PCD
%orthogonalization. Also, in this case, there must be no bias in the first
%hidded layer, and the activation function must be linear.
if length(trfFunc) > 2,
  multiLayer = true;
  usingBias(1) = false;
  trfFunc{1} = 'purelin';
  disp('Extracting via Caloba Style');
else
  disp('Extracting via Seixas Style');
  multiLayer = false;
end


%Initializing the output vectors.
pcd = [];
bias = [];
outNet = cell(1,maxNumPCD);
trnEvo = cell(1,maxNumPCD);
maxEfic = zeros(1,maxNumPCD);

%Will count how many PCDs were actually extracted.
pcdExtracted = 1;

%It is considered a failure if the PCD max SP is less than minDiff the
%previous one. Then , if 'maxFail' failures occur, in a sequence, the PCD
%extraction is aborted. But mxCount is reset to zero if, after a failure,
%the next extraction is successfull.
maxFail = 3;
mfCount = 0;
prevMaxSP = 0;
spDiff = 0;

%Extracting one PCD per iteration.
for i=1:maxNumPCD,
  pcdExtracted = i;
  fprintf('Extracting PCD number %d (SP diff = %f)\n', pcdExtracted, spDiff);
  
  
  trnNet = stdPCD(pcd, bias, trnAlgo, numNodes, trfFunc, usingBias, trnParam);

  if (multiLayer && i>1),
    [inTrn, inVal, inTst] = forceOrthogonalization(pcd(end,:), inTrn, inVal, inTst);
  end
  
  %Doing the training.
  [outNet{i}, trnEvo{i}, maxEfic(i)] = doTrain(trnNet, inTrn, inVal, inTst, numIterations, (multiLayer && i>1));
  maxSP = 100*maxEfic(i);
  
  pcd2Save = outNet{i}.IW{1}(end,:);
  if multiLayer, %Unit norm if Caloba Style.
    pcd2Save = pcd2Save ./ norm(pcd2Save);
  end
  pcd = [pcd; pcd2Save];
  bias = outNet{i}.b{1};

  %If the SP increment is not above the minimum threshold, we initiate the
  %stopping countdown.
  spDiff = 100 * (maxSP-prevMaxSP) / maxSP;
  if (spDiff < minDiff)
    mfCount = mfCount + 1;
  else
    mfCount = 0; %Stopping the countdown for the moment.
  end
  
  if (nPCD == 0) && (mfCount == maxFail),
    break; %We end the PCD extraction
  end
  
  % We move on to the next PCD.
  prevMaxSP = maxSP;
end

%Returning the PCDs actually extracted.
pcd = pcd(1:pcdExtracted,:);
outNet = outNet(1:pcdExtracted);
trnEvo = trnEvo(1:pcdExtracted);
efficVec = maxEfic(1:pcdExtracted);



function net = stdPCD(pcd, bias, trnAlgo, numNodes, trfFunc, usingBias, trnParam)
  nPCD = size(pcd,1);
  numNodes.hidNodes(1) = nPCD + 1; %Increasing the number of nodes in the first hidden layers.
  net = newff2(numNodes.inRange, numNodes.outRange, numNodes.hidNodes, trfFunc, trnAlgo);
  net.trainParam = trnParam;
  
  for i=1:length(net.layers),
    net.layers{i}.userdata.usingBias = usingBias(i);
  end
  
  %Getting the PCDs extracted so far, and freezing them.
  if (nPCD>=1),
    net.IW{1}(1:nPCD,:) = pcd;
    net.b{1}(1:nPCD) = bias;
    net.layers{1}.userdata.frozenNodes = (1:nPCD);
  end


  
function [trn, val, tst] = forceOrthogonalization(lastPCD, trn, val, tst)
  %If we  have already extracted a PCD, we remove
  % the information of the last PCD from the init values of the
  % new PCD to be extracted, and also from the input data.
  
  disp('Extracting the residual information for the next component.')
    
  %Removing the info related to the last PCD extracted.
  Nc = length(trn);
  for i=1:Nc,
    trn{i} = trn{i} - ( lastPCD' * (lastPCD * trn{i}) );
    val{i} = val{i} - ( lastPCD' * (lastPCD * val{i}) );
    tst{i} = tst{i} - ( lastPCD' * (lastPCD * tst{i}) );
  end

  
  function iw = ortWeights(iw)
    disp('Pointing the initial weights of the new PCD to the right direction.');
    sw = iw(end,:);
    for i=1:(size(iw,1)-1)
      pw = iw(i,:);
      iw(end,:) = iw(end,:) - ( (pw*sw') / (pw*pw') )*pw;
    end

  
function [bNet, bEvo, maxSP] = doTrain(net, inTrn, inVal, inTst, numTrains, ortWeight)
  netVec = cell(1,numTrains);
  trnVec = cell(1,numTrains);
  spVec = zeros(1, numTrains);
  nClasses = length(inTrn);

  for i=1:numTrains,
    net = scrambleWeights(net);
    
    if ortWeight,
      net.IW{1} = ortWeights(net.IW{1});
    end
    
    [netVec{i}, trnVec{i}] = ntrain(net, inTrn, inVal);
    out = nsim(netVec{i}, inTst);
  
    if nClasses > 2,
      spVec(i) = calcSP(diag(genConfMatrix(out)));
    else
      spVec(i) = max(genROC(out{1}, out{2}));
    end
  end

  [maxSP, idx] = max(spVec);
  bNet = netVec{idx};
  bEvo = trnVec{idx};


function [trnAlgo, maxNumPCD, numNodes, trfFunc, usingBias, trnParam] = getNetworkInfo(net)
  %Getting the network information regarding its topology

  %Taking the training algo.
  trnAlgo = net.trainFcn;

  %The maximum number of PCDs to be extracted is equal to the input size.
  maxNumPCD = net.inputs{1}.size;
  
  %Getting the input and output ranges.
  numNodes.inRange = net.inputs{1}.range;
  numNodes.outRange = net.outputs{length(net.outputs)}.range;

  %Taking the other layer's size and training function.
  numNodes.hidNodes = zeros(1,(length(net.layers)-1));
  trfFunc = cell(1,length(net.layers));
  usingBias = zeros(1,length(net.layers));
  for i=1:length(net.layers),
    if i < length(net.layers),
      numNodes.hidNodes(i) = net.layers{i}.size;
    end
    trfFunc{i} = net.layers{i}.transferFcn;
    usingBias(i) = net.layers{i}.userdata.usingBias;
  end
  
  trnParam = net.trainParam;
