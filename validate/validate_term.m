clear all;
close all;

%Creating the data for validation.
nClasses = 2;
c1 = single([randn(1,3000); randn(1,3000)]);
c2 = single([2.5 + randn(1,3000); 2.5 + randn(1,3000)]);

%Creating the neural network.
net = newff2([nClasses,2,1], {'tansig', 'tansig'});
net.trainParam.epochs = 3000;
net.trainParam.max_fail = 20;
net.trainParam.show = 1;
batchSize = 10;


%Creating the training, validating and testing data sets.
inTrn = {c1(:,1:3:end) c2(:,1:3:end)};
inVal = {c1(:,2:3:end) c2(:,2:3:end)};
inTst = {c1(:,3:3:end) c2(:,3:3:end)};
contInTrn = [inTrn{1} inTrn{2}];
contInVal = [inVal{1} inVal{2}];
contInTst = [inTst{1} inTst{2}];
outTrn = [ones(1, size(inTrn{1},2), 'single') -ones(1, size(inTrn{2},2), 'single')];
outVal = [ones(1, size(inVal{1},2), 'single') -ones(1, size(inVal{2},2), 'single')];
outTst = single([ones(1, size(inTst{1},2), 'single') -ones(1, size(inTst{2},2), 'single')]);

%Training the networks to be compared.
tic
[fastNetCont, contE, contTrnE, contValE] = ntrain(net, contInTrn, outTrn, contInVal, outVal, batchSize);
toc

tic
[fastNet, e, trnE, valE] = ntrain(net, inTrn, inVal, batchSize);
toc

%Generating the testing outputs.
fastNetContOut = {nsim(fastNetCont, inTst{1}) nsim(fastNetCont, inTst{2})};
fastNetOut = nsim(fastNet, inTst);

%First analysis: RoC.
[fastNetContSP, fastNetContCut, fastNetContDet, fastNetContFa] = genROC(fastNetContOut{1}, fastNetContOut{2});
[fastNetContMaxSP fastNetContIdx] = max(fastNetContSP);
[fastNetSP, fastNetCut, fastNetDet, fastNetFa] = genROC(fastNetOut{1}, fastNetOut{2}); 
[fastNetMaxSP fastNetIdx] = max(fastNetSP);
 
figure;

subplot(2,2,1);
plot(fastNetContFa, fastNetContDet, 'r-');
hold on;
plot(fastNetFa, fastNetDet, 'k-');
legend(sprintf('FastNet (cont) (SP = %f)', fastNetContMaxSP), sprintf('FastNet (SP = %f)', fastNetMaxSP), 'Location', 'SouthEast');
plot(fastNetContFa(fastNetContIdx), fastNetContDet(fastNetContIdx), 'rx');
plot(fastNetFa(fastNetIdx), fastNetDet(fastNetIdx), 'k*');
title('RoC Between the Algorithms');
xlabel('False Alarm (%)');
ylabel('Detection (%)');

subplot(2,2,2);
plot(contE, contTrnE, 'b-', contE, contValE,'r-', e, trnE, 'k-', e, valE,'m-');
legend('Trn (cont)', 'Val (cont)', 'Trn', 'Val');
title('Trining Evolution');
xlabel('Epoch');
ylabel('MSE');

%Second analysis: output distribution.
nBims = 200;
subplot(2,2,3);
histLog(fastNetContOut, nBims);
title('Output Distribution for the FastNet (Cont) Version')
xlabel('Network Output');
subplot(2,2,4);
histLog(fastNetOut, nBims);
title('Output Distribution for the FastNet Version')
xlabel('Network Output');
