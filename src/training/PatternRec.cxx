#include "fastnet/training/PatternRec.h"

PatternRecognition::PatternRecognition(const mxArray *inTrn, const mxArray *inVal, const bool usingSP) : Training()
{
  DEBUG1("Starting a Pattern Recognition Training Object");
  if (mxGetN(inTrn) != mxGetN(inVal)) throw "Number of training and validating patterns are not equal";
  
  useSP = usingSP;
  if (useSP)
  {
    bestGoal = 0.;
    DEBUG2("I'll use SP validating criterium.");
  }
  else DEBUG2("I'll NOT use SP validating criterium.");
  
  numPatterns = mxGetN(inTrn);
  DEBUG2("Number of patterns: " << numPatterns);
  outputSize = (numPatterns == 2) ? 1 : numPatterns;
  inTrnList = new const REAL* [numPatterns];
  inValList = new const REAL* [numPatterns];
  targList = new const REAL* [numPatterns];
  if (useSP) epochValOutputs = new REAL* [numPatterns];
  numTrnEvents = new unsigned [numPatterns];
  numValEvents = new unsigned [numPatterns];
  
  for (unsigned i=0; i<numPatterns; i++)
  {
    const mxArray *patTrnData = mxGetCell(inTrn, i);
    const mxArray *patValData = mxGetCell(inVal, i);    

    //Checking whether the dimensions are ok.
    if ( mxGetM(patTrnData) != mxGetM(patValData) ) throw "Input training and validating events dimension does not match!";
    if ( (i) and (mxGetM(patTrnData) != inputSize)) throw "Events dimension between patterns does not match!";
    else inputSize = mxGetM(patTrnData);

    //Getting the desired values.    
    inTrnList[i] = static_cast<REAL*>(mxGetData(patTrnData));
    inValList[i] = static_cast<REAL*>(mxGetData(patValData));
    numTrnEvents[i] = mxGetN(patTrnData);
    numValEvents[i] = mxGetN(patValData);
    if (useSP) epochValOutputs[i] = new REAL [outputSize*numValEvents[i]];
    DEBUG2("Number of training events for pattern " << i << ": " << numTrnEvents[i]);
    DEBUG2("Number of validating events for pattern " << i << ": " << numValEvents[i]);
    
    //Generating the desired output for each pattern for maximum sparsed outputs.
    REAL *target = new REAL [outputSize];
    for (unsigned j=0; j<outputSize; j++) target[j] = -1;
    target[i] = 1;
    //Saving the target in the list.
    targList[i] = target;    
  }
  
  DEBUG2("Input events dimension: " << inputSize);
  DEBUG2("Output events dimension: " << outputSize);
};

PatternRecognition::~PatternRecognition()
{
  delete [] numTrnEvents;
  delete [] numValEvents;
  for (unsigned i=0; i<numPatterns; i++)
  {
    delete [] inTrnList[i];
    delete [] inValList[i];
    delete [] targList[i];
    if (useSP) delete [] epochValOutputs[i];
  }
  delete [] inTrnList;
  delete [] inValList;
  delete [] targList;
  if (useSP) delete [] epochValOutputs;
};

REAL PatternRecognition::sp()
{
  unsigned TARG_SIGNAL, TARG_NOISE;
  
  //We consider that our signal has target output +1 and the noise, -1. So, the if below help us
  //figure out which class is the signal.
  if (targList[0][0] > targList[1][0]) // target[0] is our signal.
  {
    TARG_NOISE = 1;
    TARG_SIGNAL = 0;    
  }
  else //target[1] is the signal.
  {
    TARG_NOISE = 0;
    TARG_SIGNAL = 1;
  }

  const REAL *signal = epochValOutputs[TARG_SIGNAL];
  const unsigned numSignalEvents = numValEvents[TARG_SIGNAL];
  const REAL *noise = epochValOutputs[TARG_NOISE];
  const unsigned numNoiseEvents = numValEvents[TARG_NOISE];
  const REAL signalTarget = targList[TARG_SIGNAL][0];
  const REAL noiseTarget = targList[TARG_NOISE][0];
  const REAL RESOLUTION = 0.001;
  REAL maxSP = -1.;

  for (REAL pos = noiseTarget; pos < signalTarget; pos += RESOLUTION)
  {
    REAL sigEffic = 0.;
    
    for (unsigned i=0; i<numSignalEvents; i++) if (signal[i] >= pos) sigEffic++;
    sigEffic /= static_cast<REAL>(numSignalEvents);

    REAL noiseEffic = 0.;
    for (unsigned i=0; i<numNoiseEvents; i++) if (noise[i] < pos) noiseEffic++;
    noiseEffic /= static_cast<REAL>(numNoiseEvents);

    //Using normalized SP calculation.
    const REAL sp = ((sigEffic + noiseEffic) / 2) * sqrt(sigEffic * noiseEffic);
    if (sp > maxSP) maxSP = sp;
  }
  return maxSP;
};

REAL PatternRecognition::valNetwork(Backpropagation *net)
{
  DEBUG2("Starting validation process for an epoch.");
  REAL gbError = 0;
  
  for (unsigned pat=0; pat<numPatterns; pat++)
  {
    //wFactor will allow each pattern to have the same relevance, despite the number of events it contains.
    const REAL wFactor = 1. / static_cast<REAL>(numPatterns * numValEvents[pat]);
    const REAL *target = targList[pat];
    const REAL *input = inValList[pat];
    const REAL *output;
    REAL *outList = (useSP) ? epochValOutputs[pat] : NULL;
    
    DEBUG3("Applying validation set for pattern " << pat << ". Weighting factor to use: " << wFactor);
    for (unsigned i=0; i<numValEvents[pat]; i++)
    {
    gbError += ( wFactor * net->applySupervisedInput(input, target, output) );
    if (useSP) outList[i] = output[0];
    input += inputSize;
    }
  }

  return (useSP) ? sp() : gbError;
};


REAL PatternRecognition::trainNetwork(Backpropagation *net)
{
  DEBUG2("Starting training process for an epoch.");
  REAL gbError = 0;
  for(unsigned pat=0; pat<numPatterns; pat++)
  {
    //wFactor will allow each pattern to have the same relevance, despite the number of events it contains.
    const REAL wFactor = 1. / static_cast<REAL>(numPatterns * numTrnEvents[pat]);
    const REAL *target = targList[pat];
    const REAL *input = inTrnList[pat];
    const REAL *output;

    DEBUG3("Applying training set for pattern " << pat << ". Weighting factor to use: " << wFactor);
    for (unsigned i=0; i<numTrnEvents[pat]; i++)
    {
    gbError += ( wFactor * net->applySupervisedInput(input, target, output));
    //Calculating the weight and bias update values.
    net->calculateNewWeights(output, target, pat);
    input += inputSize;
    }
  }

  return gbError;  
};
  
void PatternRecognition::checkSizeMismatch(const Backpropagation *net) const
{
  if (inputSize != (*net)[0]) throw "Input training or validating data do not match the network input layer size!";
};


void PatternRecognition::showInfo(const unsigned nEpochs) const
{
  REPORT("TRAINING DATA INFORMATION (Pattern Recognition Optimized Network)");
  REPORT("Number of Epochs          : " << nEpochs);
  REPORT("Using SP Stopping Criteria      : " << (useSP) ? "true" : "false");
  for (unsigned i=0; i<numPatterns; i++)
  {
    REPORT("Information for pattern " << (i+1) << ":");
    REPORT("Total number of training events   : " << numTrnEvents[i]);
    REPORT("Total number of validating events    : " << numValEvents[i]);
  }
};

bool PatternRecognition::isBestNetwork(const REAL currError)
{
  if (useSP)
  {
    if (currError > bestGoal)
    {
    bestGoal = currError;
    return true;
    }
    return false;
  }
  
  //Otherwise we use the standard MSE method.
  return Training::isBestNetwork(currError);
};

void PatternRecognition::showTrainingStatus(const unsigned epoch, const REAL trnError, const REAL valError)
{
  if (useSP) {REPORT("Epoch " << setw(5) << epoch << ": mse (train) = " << trnError << "SP (val) = " << valError)}
  else Training::showTrainingStatus(epoch, trnError, valError);
};